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
final class DashboardController {
    private static let totalWidth: CGFloat = 685
    private static let reservedWidth: CGFloat = 130
    private static let bubbleMaxWidth: CGFloat = 360
    private static let barHeight: CGFloat = 30

    private static let avatarID = NSTouchBarItem.Identifier("ca.spollock.touchbuddy.dashboard.avatar")
    private static let bubbleID = NSTouchBarItem.Identifier("ca.spollock.touchbuddy.dashboard.bubble")
    private static let chipsID = NSTouchBarItem.Identifier("ca.spollock.touchbuddy.dashboard.chips")

    private let prefs: Preferences
    private let frames: FrameCache
    private let fallback: CharacterDescriptor?
    private let onChipTap: (SessionRecord) -> Void
    private let speaker = Speaker()

    private let bar = NSTouchBar()
    private let avatarView = SizedView()
    private let sprite = SpriteView(frame: .zero)
    private let bubbleView = SizedView()
    private let marquee = MarqueeLabel(frame: .zero)
    private let chipsScroll = ChipsScrollView()

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
        onChipTap: @escaping (SessionRecord) -> Void
    ) {
        self.prefs = prefs
        self.frames = frames
        self.fallback = fallback
        self.onChipTap = onChipTap
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

        bar.defaultItemIdentifiers = [Self.avatarID, Self.bubbleID, Self.chipsID]
        bar.templateItems = [avatarItem, bubbleItem, chipsItem]
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
        layoutBubble(text: line ?? "")
        layoutChips(now: now, focusID: focus?.sessionID)
        return repick
    }

    private var bubbleWidth: CGFloat = 0

    private func layoutBubble(text: String) {
        let width = min(MarqueeLabel.measure(text) + 24, Self.bubbleMaxWidth)
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
        let available = max(120, Self.totalWidth - Self.reservedWidth - bubbleWidth)
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
}
