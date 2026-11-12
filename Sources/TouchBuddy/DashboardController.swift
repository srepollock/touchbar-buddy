import AppKit
import OSLog
import TouchBarPrivate
import TouchBuddyCore

private let logger = Logger(subsystem: "ca.spollock.touchbuddy", category: "dashboard")

@MainActor
private final class SizedView: NSView {
    var fixedSize: NSSize?

    override var intrinsicContentSize: NSSize {
        fixedSize ?? super.intrinsicContentSize
    }
}

@MainActor
private final class ChipsScrollView: NSScrollView {
    var width: CGFloat = 0 {
        didSet { invalidateIntrinsicContentSize() }
    }

    override var intrinsicContentSize: NSSize { NSSize(width: width, height: 30) }
}

@MainActor
private final class ReplyButton: NSButton {
    private let handler: () -> Void

    init(accessibilityLabel: String, onTap: @escaping () -> Void) {
        handler = onTap
        super.init(frame: .zero)
        isBordered = true
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(fire)
        lineBreakMode = .byTruncatingTail
        setAccessibilityLabel(accessibilityLabel)
    }

    required init?(coder: NSCoder) { nil }

    @objc private func fire() { handler() }
}

@MainActor
final class DashboardController {
    private static let totalWidth: CGFloat = 685
    private static let avatarSlotWidth: CGFloat = 52
    private static let spriteSize: CGFloat = 30
    private static let reservedWidth: CGFloat = 94 + avatarSlotWidth
    private static let strollLaneWidth: CGFloat = totalWidth - 94 - 6
    private static let strollSeconds: TimeInterval = 6
    private static let strollBubbleMaxWidth: CGFloat = 300
    private static let strollGap: CGFloat = 4
    private static let paceAmplitude: CGFloat = 8
    private static let paceQuietSeconds: TimeInterval = 4
    private static let bubbleMaxWidth: CGFloat = 360
    private static let barHeight: CGFloat = 30

    private static let avatarID = NSTouchBarItem.Identifier("ca.spollock.touchbuddy.dashboard.avatar")
    private static let bubbleID = NSTouchBarItem.Identifier("ca.spollock.touchbuddy.dashboard.bubble")
    private static let chipsID = NSTouchBarItem.Identifier("ca.spollock.touchbuddy.dashboard.chips")
    private static let repliesID = NSTouchBarItem.Identifier("ca.spollock.touchbuddy.dashboard.replies")

    private static let bubbleMinWidth: CGFloat = 80
    private static let chipsMinWidth: CGFloat = 120
    private static let itemSpacing: CGFloat = 8
    private static let replyGap: CGFloat = 6
    private static let allowGreen = NSColor(srgbRed: 0x7E / 255, green: 0xD3 / 255, blue: 0x21 / 255, alpha: 1)
    private static let denyRed = NSColor(srgbRed: 0xE5 / 255, green: 0x48 / 255, blue: 0x4D / 255, alpha: 1)

    private let prefs: Preferences
    private let frames: FrameCache
    private let fallback: CharacterDescriptor?
    private let onChipTap: (SessionRecord) -> Void
    private let onReply: (QuickReply, SessionRecord) -> Bool
    private let speaker = Speaker()

    private let bar = NSTouchBar()
    private let avatarView = SizedView()
    private let sprite = SpriteView(frame: .zero)
    private let bubbleView = SizedView()
    private let marquee = MarqueeLabel(frame: .zero)
    private let chipsScroll = ChipsScrollView()
    private let repliesView = SizedView()
    private var replyButtons: [NSButton] = []
    private var replyShownFor: SessionRecord?
    private var repliesWidth: CGFloat = 0
    private var replyBuiltAt = Date.distantPast

    private var sessions: [SessionRecord] = []
    private var focusID: String?
    private var character: CharacterDescriptor?
    private var isPresented = false
    private var pinned = false
    private var sawVisible = false
    private var visibilityObservation: NSKeyValueObservation?
    private var isProgrammaticChipScroll = false
    private var lastChipOffset: CGFloat = 0
    private var dismissTimer: Timer?
    private var lastSpeechKey: SpeechKey?
    private var lastSpeechCharacterID: String?
    private var line: String?
    private var lineSessionID: String?

    private let strollBubble = SizedView()
    private let strollMarquee = MarqueeLabel(frame: .zero)
    private var isStrolling = false
    private var strollSessionID: String?
    private var strollStartedAt = Date()
    private var strollTimer: Timer?
    private var strollGroupWidth: CGFloat = 0
    private var paceTimer: Timer?
    private var avatarButton = TapButton(accessibilityLabel: "Talk to TouchBuddy") {}

    init(
        prefs: Preferences, frames: FrameCache, fallback: CharacterDescriptor?,
        onChipTap: @escaping (SessionRecord) -> Void,
        onReply: @escaping (QuickReply, SessionRecord) -> Bool
    ) {
        self.prefs = prefs
        self.frames = frames
        self.fallback = fallback
        self.onChipTap = onChipTap
        self.onReply = onReply
        TBPShowCloseBoxWhenFrontMost(true)
        buildBar()
        visibilityObservation = bar.observe(\.isVisible, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.visibilityChanged() }
        }
    }

    func show(
        sessions: [SessionRecord], focus: SessionRecord?, character: CharacterDescriptor, autoDismiss: Bool
    ) {
        cancelDismissTimer()
        speaker.stop()
        endStroll(render: false)
        if !autoDismiss { pinned = true }
        self.sessions = sessions
        self.focusID = focus?.sessionID
        self.character = character
        replyShownFor = nil
        let picked = render(now: Date())

        TBPPresentSystemModal(bar, ControlStripController.identifier)
        isPresented = true
        marquee.isActive = true
        noteLineChanged()
        logger.info("presented dashboard autoDismiss=\(autoDismiss, privacy: .public) pinned=\(self.pinned, privacy: .public) sessions=\(sessions.count, privacy: .public)")

        if autoDismiss {
            if !pinned { scheduleDismiss() }
            if picked, prefs.ttsEnabled, let line {
                speaker.speak(line, voice: character.manifest.voice)
            }
        }
    }

    /// True while the owner has the dashboard open or has touched it; new popups must not retarget it.
    var isPinnedOpen: Bool { isPresented && pinned }

    /// True while any dashboard (including an ambient stroll) is up.
    var isOpen: Bool { isPresented }

    func showAmbient(session: SessionRecord, sessions: [SessionRecord], character: CharacterDescriptor) {
        guard !isPresented else { return }
        cancelDismissTimer()
        speaker.stop()
        pinned = false
        self.sessions = sessions
        focusID = session.sessionID
        self.character = character
        replyShownFor = nil

        let fallbackSpeech = fallback?.manifest.speech ?? SpeechTemplates(lines: [:])
        let text = speechLine(
            for: session, templates: character.manifest.speech ?? fallbackSpeech,
            fallback: fallbackSpeech, pick: { $0.randomElement() }
        )
        line = text
        lineSessionID = session.sessionID
        lastSpeechKey = nil
        lastSpeechCharacterID = nil

        if let resolved = frames.resolve(character: character, fallback: fallback, state: .working) {
            sprite.play(resolved.frames, key: resolved.key)
        } else {
            sprite.stop()
        }
        beginStroll(sessionID: session.sessionID, text: text)

        TBPPresentSystemModal(bar, ControlStripController.identifier)
        isPresented = true
        strollMarquee.isActive = true
        logger.info("presented ambient stroll session=\(session.sessionID, privacy: .public)")
        scheduleDismiss(after: Self.strollSeconds)
    }

    func refresh(sessions: [SessionRecord]) {
        guard isPresented, character != nil else { return }
        self.sessions = sessions
        if isStrolling { return }
        render(now: Date())
    }

    func dismiss() {
        let wasPresented = isPresented
        teardown()
        if wasPresented {
            TBPMinimizeSystemModal(bar)
            logger.info("minimized dashboard")
        }
    }

    private func teardown() {
        cancelDismissTimer()
        speaker.stop()
        pinned = false
        isPresented = false
        replyShownFor = nil
        marquee.isActive = false
        strollMarquee.isActive = false
        cancelPaceTimer()
        endStroll(render: false)
        sprite.stop()
    }

    private func userInteracted() {
        guard isPresented else { return }
        pinned = true
        cancelDismissTimer()
        if isStrolling { endStroll(render: true) }
    }

    // MARK: Chatty: stroll, pacing, avatar tap

    private func beginStroll(sessionID: String, text: String) {
        setReplies([], shownFor: nil)
        isStrolling = true
        strollSessionID = sessionID
        bar.defaultItemIdentifiers = [Self.avatarID]

        let bubbleWidth = min(MarqueeLabel.measure(text) + 24, Self.strollBubbleMaxWidth)
        strollGroupWidth = Self.spriteSize + Self.strollGap + bubbleWidth
        strollBubble.frame = NSRect(x: 0, y: 0, width: bubbleWidth, height: Self.barHeight)
        strollMarquee.frame = NSRect(x: 12, y: 0, width: bubbleWidth - 24, height: Self.barHeight)
        strollMarquee.text = text
        avatarView.addSubview(strollBubble)

        avatarView.fixedSize = NSSize(width: Self.strollLaneWidth, height: Self.barHeight)
        avatarView.frame = NSRect(x: 0, y: 0, width: Self.strollLaneWidth, height: Self.barHeight)
        avatarButton.frame = avatarView.bounds
        avatarView.invalidateIntrinsicContentSize()
        cancelPaceTimer()
        sprite.stopPacing()

        strollStartedAt = Date()
        strollTick()
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.strollTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        strollTimer = timer
    }

    private func strollTick() {
        let position = strollPosition(
            elapsed: Date().timeIntervalSince(strollStartedAt), duration: Self.strollSeconds,
            laneWidth: Self.strollLaneWidth, spriteWidth: strollGroupWidth
        )
        sprite.frame.origin.x = position.x
        sprite.facingLeft = position.facingLeft
        strollBubble.frame.origin.x = position.x + Self.spriteSize + Self.strollGap
    }

    private func endStroll(render shouldRender: Bool) {
        strollTimer?.invalidate()
        strollTimer = nil
        guard isStrolling else { return }
        isStrolling = false
        strollSessionID = nil
        strollMarquee.isActive = false
        strollBubble.removeFromSuperview()
        sprite.facingLeft = false
        avatarView.fixedSize = NSSize(width: Self.avatarSlotWidth, height: Self.barHeight)
        avatarView.frame = NSRect(x: 0, y: 0, width: Self.avatarSlotWidth, height: Self.barHeight)
        sprite.frame = Self.spriteSlotFrame
        avatarButton.frame = avatarView.bounds
        avatarView.invalidateIntrinsicContentSize()
        lastSpeechKey = nil
        if shouldRender {
            marquee.isActive = true
            render(now: Date())
            noteLineChanged()
        }
    }

    private static var spriteSlotFrame: NSRect {
        NSRect(x: (avatarSlotWidth - spriteSize) / 2, y: 0, width: spriteSize, height: barHeight)
    }

    /// Restarts the 4 s quiet period after which the avatar paces within its slot.
    private func noteLineChanged() {
        cancelPaceTimer()
        sprite.settlePacing()
        guard isPresented, !isStrolling else { return }
        let timer = Timer(timeInterval: Self.paceQuietSeconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isPresented, !self.isStrolling else { return }
                self.sprite.startPacing(amplitude: Self.paceAmplitude)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        paceTimer = timer
    }

    private func cancelPaceTimer() {
        paceTimer?.invalidate()
        paceTimer = nil
    }

    private func avatarTapped() {
        userInteracted()
        guard isPresented, let character else { return }
        let now = Date()
        let target = avatarTapTarget(
            sessions: sessions, focusID: focusID, repliesShowing: replyShownFor != nil, now: now,
            pick: { $0.randomElement() }
        )
        let fallbackSpeech = fallback?.manifest.speech ?? SpeechTemplates(lines: [:])
        let text = speechLine(
            for: target, templates: character.manifest.speech ?? fallbackSpeech,
            fallback: fallbackSpeech, pick: { $0.randomElement() }
        )
        line = text
        lineSessionID = target?.sessionID
        layoutBubble(text: text)
        layoutChips(now: now, focusID: focusID)
        logger.info("avatar tapped, talking about session=\(target?.sessionID ?? "none", privacy: .public)")

        if let hop = frames.resolve(character: character, fallback: fallback, state: .finished) {
            sprite.playOnce(hop.frames) { [weak self] in self?.playStateAnimation(now: Date()) }
        }
        noteLineChanged()
    }

    private func playStateAnimation(now: Date) {
        guard isPresented, !isStrolling, let character else { return }
        let focus = sessions.first { $0.sessionID == focusID } ?? sessions.first
        let state = focus.map { effectiveState($0, now: now) } ?? .idle
        if let resolved = frames.resolve(character: character, fallback: fallback, state: state) {
            sprite.play(resolved.frames, key: resolved.key)
        } else {
            sprite.stop()
        }
    }

    private func visibilityChanged() {
        logger.info("dashboard visible=\(self.bar.isVisible, privacy: .public)")
        if bar.isVisible {
            sawVisible = true
        } else if sawVisible {
            sawVisible = false
            teardown()
        }
    }

    private func scheduleDismiss(after seconds: TimeInterval? = nil) {
        cancelDismissTimer()
        let timer = Timer(timeInterval: seconds ?? prefs.popupSeconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }
        RunLoop.main.add(timer, forMode: .common)
        dismissTimer = timer
    }

    private func cancelDismissTimer() {
        dismissTimer?.invalidate()
        dismissTimer = nil
    }

    private func buildBar() {
        avatarView.fixedSize = NSSize(width: Self.avatarSlotWidth, height: Self.barHeight)
        sprite.frame = Self.spriteSlotFrame
        avatarView.addSubview(sprite)
        avatarButton = TapButton(accessibilityLabel: "Talk to TouchBuddy") { [weak self] in self?.avatarTapped() }
        avatarButton.frame = avatarView.bounds
        avatarView.addSubview(avatarButton)
        strollMarquee.onUserScroll = { [weak self] in self?.userInteracted() }

        bubbleView.wantsLayer = true
        bubbleView.layer?.cornerRadius = 12
        bubbleView.layer?.backgroundColor = NSColor(white: 1, alpha: 0.14).cgColor
        bubbleView.addSubview(marquee)
        marquee.onUserScroll = { [weak self] in self?.userInteracted() }
        strollBubble.wantsLayer = true
        strollBubble.layer?.cornerRadius = 12
        strollBubble.layer?.backgroundColor = NSColor(white: 1, alpha: 0.14).cgColor
        strollBubble.addSubview(strollMarquee)
        let strollTap = NSClickGestureRecognizer(target: self, action: #selector(strollBubbleTapped(_:)))
        strollTap.allowedTouchTypes = .direct
        strollTap.numberOfClicksRequired = 1
        strollMarquee.addGestureRecognizer(strollTap)

        let bubbleTap = NSClickGestureRecognizer(target: self, action: #selector(bubbleTapped(_:)))
        bubbleTap.allowedTouchTypes = .direct
        bubbleTap.numberOfClicksRequired = 1
        marquee.addGestureRecognizer(bubbleTap)

        chipsScroll.drawsBackground = false
        chipsScroll.hasHorizontalScroller = false
        chipsScroll.hasVerticalScroller = false
        chipsScroll.horizontalScrollElasticity = .allowed
        chipsScroll.verticalScrollElasticity = .none
        chipsScroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: chipsScroll.contentView, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isProgrammaticChipScroll,
                      abs(self.chipsScroll.contentView.bounds.origin.x - self.lastChipOffset) > 0.5
                else { return }
                self.userInteracted()
            }
        }

        let avatarItem = NSCustomTouchBarItem(identifier: Self.avatarID)
        avatarItem.view = avatarView
        let bubbleItem = NSCustomTouchBarItem(identifier: Self.bubbleID)
        bubbleItem.view = bubbleView
        let chipsItem = NSCustomTouchBarItem(identifier: Self.chipsID)
        chipsItem.view = chipsScroll

        let repliesItem = NSCustomTouchBarItem(identifier: Self.repliesID)
        repliesItem.view = repliesView

        bar.defaultItemIdentifiers = [Self.avatarID, Self.bubbleID, Self.chipsID]
        bar.templateItems = [avatarItem, bubbleItem, repliesItem, chipsItem]
    }

    @objc private func strollBubbleTapped(_ recognizer: NSClickGestureRecognizer) {
        guard recognizer.state == .ended, let id = strollSessionID,
              let session = sessions.first(where: { $0.sessionID == id })
        else { return }
        logger.info("stroll bubble tapped session=\(id, privacy: .public)")
        onChipTap(session)
    }

    @objc private func bubbleTapped(_ recognizer: NSClickGestureRecognizer) {
        guard recognizer.state == .ended, !marquee.isUserScrolling else { return }
        let target = replyShownFor != nil ? focusID : (lineSessionID ?? focusID)
        guard let focus = sessions.first(where: { $0.sessionID == target })
            ?? sessions.first(where: { $0.sessionID == focusID }) ?? sessions.first
        else { return }
        logger.info("bubble tapped session=\(focus.sessionID, privacy: .public)")
        onChipTap(focus)
    }

    @discardableResult
    private func render(now: Date) -> Bool {
        guard let character else { return false }
        let focus = sessions.first { $0.sessionID == focusID } ?? sessions.first
        let state = focus.map { effectiveState($0, now: now) } ?? .idle

        if let resolved = frames.resolve(character: character, fallback: fallback, state: state) {
            sprite.play(resolved.frames, key: resolved.key)
        } else {
            sprite.stop()
        }

        let key = speechKey(for: focus)
        let repick = shouldRepickSpeech(previous: lastSpeechKey, current: key, hasLine: line != nil)
            || lastSpeechCharacterID != character.id
        if repick {
            let fallbackSpeech = fallback?.manifest.speech ?? SpeechTemplates(lines: [:])
            line = speechLine(
                for: focus,
                templates: character.manifest.speech ?? fallbackSpeech,
                fallback: fallbackSpeech,
                pick: { $0.randomElement() }
            )
            lastSpeechKey = key
            lastSpeechCharacterID = character.id
            lineSessionID = nil
            noteLineChanged()
        }
        layoutReplies(for: focus)
        layoutBubble(text: line ?? "")
        layoutChips(now: now, focusID: focus?.sessionID)
        return repick
    }

    private var bubbleWidth: CGFloat = 0

    private func layoutBubble(text: String) {
        let repliesSpace = repliesWidth > 0 ? repliesWidth + Self.itemSpacing : 0
        let chipsSpace = sessions.isEmpty ? 0 : Self.chipsMinWidth
        let cap = max(
            Self.bubbleMinWidth,
            min(Self.bubbleMaxWidth, Self.totalWidth - Self.reservedWidth - repliesSpace - chipsSpace)
        )
        let width = min(MarqueeLabel.measure(text) + 24, cap)
        bubbleWidth = width
        bubbleView.fixedSize = NSSize(width: width, height: Self.barHeight)
        bubbleView.frame = NSRect(x: 0, y: 0, width: width, height: Self.barHeight)
        bubbleView.invalidateIntrinsicContentSize()
        marquee.frame = NSRect(x: 12, y: 0, width: width - 24, height: Self.barHeight)
        marquee.text = text
    }

    private func layoutChips(now: Date, focusID: String?) {
        let previousOffset = chipsScroll.contentView.bounds.origin.x
        isProgrammaticChipScroll = true
        defer { isProgrammaticChipScroll = false }
        let document = NSView()
        var x: CGFloat = 0
        for session in sessions {
            let chip = makeChip(for: session, now: now, focused: session.sessionID == focusID)
            chip.frame.origin = NSPoint(x: x, y: 0)
            document.addSubview(chip)
            x += chip.frame.width + 6
        }
        let contentWidth = max(0, x - 6)
        document.frame = NSRect(x: 0, y: 0, width: contentWidth, height: Self.barHeight)
        let repliesSpace = repliesWidth > 0 ? repliesWidth + Self.itemSpacing : 0
        let available = max(Self.chipsMinWidth, Self.totalWidth - Self.reservedWidth - bubbleWidth - repliesSpace)
        chipsScroll.width = min(contentWidth, available)
        chipsScroll.documentView = document
        chipsScroll.frame.size = NSSize(width: chipsScroll.width, height: Self.barHeight)
        chipsScroll.isHidden = sessions.isEmpty
        let maxOffset = max(0, contentWidth - chipsScroll.width)
        lastChipOffset = min(max(0, previousOffset), maxOffset)
        chipsScroll.contentView.scroll(to: NSPoint(x: lastChipOffset, y: 0))
        chipsScroll.reflectScrolledClipView(chipsScroll.contentView)
    }

    private func makeChip(for session: SessionRecord, now: Date, focused: Bool) -> NSView {
        let title = chipTitle(session.projectName)
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .white
        label.sizeToFit()
        let labelHeight = label.frame.height
        let width = 10 + 8 + 6 + ceil(label.frame.width) + 10

        let chip = NSView()
        chip.wantsLayer = true
        chip.layer?.cornerRadius = 12
        chip.layer?.backgroundColor = NSColor(white: 1, alpha: focused ? 0.26 : 0.12).cgColor
        chip.frame = NSRect(x: 0, y: 0, width: width, height: Self.barHeight)

        let dot = NSView(frame: NSRect(x: 10, y: (Self.barHeight - 8) / 2, width: 8, height: 8))
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        dot.layer?.backgroundColor = statusColor(effectiveState(session, now: now)).cgColor
        chip.addSubview(dot)

        label.frame.origin = NSPoint(x: 24, y: (Self.barHeight - labelHeight) / 2)
        chip.addSubview(label)

        let button = TapButton(accessibilityLabel: session.projectName) { [weak self] in self?.onChipTap(session) }
        button.frame = chip.bounds
        chip.addSubview(button)
        return chip
    }

    // MARK: Quick replies

    private func layoutReplies(for focus: SessionRecord?) {
        let replies = focus.map(quickReplies(for:)) ?? []
        guard let focus, !replies.isEmpty else {
            setReplies([], shownFor: nil)
            return
        }
        if let shown = replyShownFor, shown.sessionID == focus.sessionID {
            if shown == focus { return }
            // A re-notification for the same tool call is still the same prompt: rebuild rather than grey for good.
            if shown.state == .needsInput, focus.state == .needsInput,
               let id = shown.pendingToolUseID, id == focus.pendingToolUseID,
               shown.toolName == focus.toolName, shown.detail == focus.detail {
                setReplies(replies, shownFor: focus)
            } else {
                disableReplies()
            }
            return
        }
        setReplies(replies, shownFor: focus)
    }

    private func setReplies(_ replies: [QuickReply], shownFor record: SessionRecord?) {
        replyShownFor = record
        replyBuiltAt = Date()
        replyButtons.forEach { $0.removeFromSuperview() }
        replyButtons = []
        let identifiers = replies.isEmpty
            ? [Self.avatarID, Self.bubbleID, Self.chipsID]
            : [Self.avatarID, Self.bubbleID, Self.repliesID, Self.chipsID]
        if bar.defaultItemIdentifiers != identifiers { bar.defaultItemIdentifiers = identifiers }
        guard let record, !replies.isEmpty else {
            repliesWidth = 0
            repliesView.fixedSize = NSSize(width: 0, height: Self.barHeight)
            repliesView.invalidateIntrinsicContentSize()
            return
        }

        let yesNo = isYesNo(replies.compactMap { if case .choose(_, let label) = $0 { label } else { nil } })
        var buttons = replies.map { makeReplyButton(for: $0, yesNo: yesNo, record: record) }
        let gaps = CGFloat(buttons.count - 1) * Self.replyGap
        let maxWidth = Self.totalWidth - Self.reservedWidth - Self.itemSpacing - Self.bubbleMinWidth - Self.chipsMinWidth
        let natural = buttons.reduce(gaps) { $0 + $1.width }
        let scale = natural > maxWidth ? (maxWidth - gaps) / (natural - gaps) : 1
        var x: CGFloat = 0
        for (index, entry) in buttons.enumerated() {
            let width = floor(entry.width * scale)
            entry.button.frame = NSRect(x: x, y: 0, width: width, height: Self.barHeight)
            repliesView.addSubview(entry.button)
            x += width + Self.replyGap
            buttons[index].width = width
        }
        replyButtons = buttons.map(\.button)
        repliesWidth = max(0, x - Self.replyGap)
        repliesView.fixedSize = NSSize(width: repliesWidth, height: Self.barHeight)
        repliesView.frame = NSRect(x: 0, y: 0, width: repliesWidth, height: Self.barHeight)
        repliesView.invalidateIntrinsicContentSize()
    }

    private func disableReplies() {
        replyButtons.forEach { $0.isEnabled = false }
    }

    private func makeReplyButton(
        for reply: QuickReply, yesNo: Bool, record: SessionRecord
    ) -> (button: NSButton, width: CGFloat) {
        let tap: () -> Void = { [weak self] in self?.replyTapped(reply) }
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 15, weight: .bold)

        func symbolButton(_ symbol: String, label: String, tint: NSColor) -> (NSButton, CGFloat) {
            let button = ReplyButton(accessibilityLabel: label, onTap: tap)
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
                .withSymbolConfiguration(symbolConfig)
            button.imagePosition = .imageOnly
            button.bezelColor = tint
            button.contentTintColor = .white
            return (button, 46)
        }

        switch reply {
        case .allow:
            return symbolButton("checkmark", label: "Allow", tint: Self.allowGreen)
        case .deny:
            return symbolButton("xmark", label: "Deny", tint: Self.denyRed)
        case .allowAlways:
            let button = ReplyButton(accessibilityLabel: "Always allow", onTap: tap)
            button.title = "Always"
            button.font = .systemFont(ofSize: 11)
            button.controlSize = .small
            return (button, ceil(MarqueeLabel.measure("Always")) + 22)
        case .choose(_, let label):
            if yesNo, let polarity = yesNoPolarity(label) {
                return polarity
                    ? symbolButton("checkmark", label: label, tint: Self.allowGreen)
                    : symbolButton("xmark", label: label, tint: Self.denyRed)
            }
            let button = ReplyButton(accessibilityLabel: label, onTap: tap)
            let title = chipTitle(label, maxChars: 14)
            button.title = title
            button.font = .systemFont(ofSize: 12)
            return (button, ceil(MarqueeLabel.measure(title)) + 24)
        }
    }

    private func replyTapped(_ reply: QuickReply) {
        guard let shown = replyShownFor else { return }
        guard isReplyTapAccepted(builtAt: replyBuiltAt, now: Date()) else {
            logger.info("reply tap ignored: buttons were just rebuilt")
            return
        }
        userInteracted()
        logger.info("reply tapped session=\(shown.sessionID, privacy: .public)")
        if onReply(reply, shown) {
            dismiss()
        } else {
            disableReplies()
        }
    }
}
