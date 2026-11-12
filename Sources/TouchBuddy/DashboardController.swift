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
    private static let reservedWidth: CGFloat = 130
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
        if !autoDismiss { pinned = true }
        self.sessions = sessions
        self.focusID = focus?.sessionID
        self.character = character
        replyShownFor = nil
        let picked = render(now: Date())

        TBPPresentSystemModal(bar, ControlStripController.identifier)
        isPresented = true
        marquee.isActive = true
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

    func refresh(sessions: [SessionRecord]) {
        guard isPresented, character != nil else { return }
        self.sessions = sessions
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
        sprite.stop()
    }

    private func userInteracted() {
        guard isPresented else { return }
        pinned = true
        cancelDismissTimer()
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

    private func scheduleDismiss() {
        cancelDismissTimer()
        let timer = Timer(timeInterval: prefs.popupSeconds, repeats: false) { [weak self] _ in
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
        avatarView.fixedSize = NSSize(width: 36, height: Self.barHeight)
        sprite.frame = NSRect(x: 3, y: 0, width: 30, height: Self.barHeight)
        avatarView.addSubview(sprite)
        let avatarButton = TapButton(accessibilityLabel: "Close dashboard") { [weak self] in self?.dismiss() }
        avatarButton.frame = avatarView.bounds
        avatarView.addSubview(avatarButton)

        bubbleView.wantsLayer = true
        bubbleView.layer?.cornerRadius = 12
        bubbleView.layer?.backgroundColor = NSColor(white: 1, alpha: 0.14).cgColor
        bubbleView.addSubview(marquee)
        marquee.onUserScroll = { [weak self] in self?.userInteracted() }
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

    @objc private func bubbleTapped(_ recognizer: NSClickGestureRecognizer) {
        guard recognizer.state == .ended, !marquee.isUserScrolling else { return }
        guard let focus = sessions.first(where: { $0.sessionID == focusID }) ?? sessions.first else { return }
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
