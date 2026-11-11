import AppKit
import OSLog
import TouchBarPrivate
import TouchBuddyCore

private let logger = Logger(subsystem: "ca.spollock.touchbuddy", category: "dashboard")

@MainActor
private final class TapView: NSView {
    var onTap: () -> Void = {}
    var fixedSize: NSSize?
    private var dragged = false

    override var intrinsicContentSize: NSSize {
        fixedSize ?? super.intrinsicContentSize
    }

    override func mouseDown(with event: NSEvent) { dragged = false }
    override func mouseDragged(with event: NSEvent) { dragged = true }
    override func mouseUp(with event: NSEvent) {
        guard !dragged else { return }
        onTap()
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
    private let avatarView = TapView()
    private let sprite = SpriteView(frame: .zero)
    private let bubbleView = TapView()
    private let marquee = MarqueeLabel(frame: .zero)
    private let chipsScroll = ChipsScrollView()

    private var sessions: [SessionRecord] = []
    private var focusID: String?
    private var character: CharacterDescriptor?
    private var isPresented = false
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
        buildBar()
    }

    func show(
        sessions: [SessionRecord], focus: SessionRecord?, character: CharacterDescriptor, autoDismiss: Bool
    ) {
        self.sessions = sessions
        self.focusID = focus?.sessionID
        self.character = character
        let picked = render(now: Date())

        TBPShowCloseBoxWhenFrontMost(true)
        TBPPresentSystemModal(bar, ControlStripController.identifier)
        isPresented = true
        marquee.isActive = true
        logger.info("presented dashboard autoDismiss=\(autoDismiss, privacy: .public) sessions=\(sessions.count, privacy: .public)")

        if autoDismiss {
            scheduleDismiss()
            if picked, prefs.ttsEnabled, let line {
                speaker.speak(line, voice: character.manifest.voice)
            }
        } else {
            cancelDismissTimer()
        }
    }

    func refresh(sessions: [SessionRecord]) {
        guard isPresented, character != nil else { return }
        self.sessions = sessions
        render(now: Date())
    }

    func dismiss() {
        cancelDismissTimer()
        speaker.stop()
        guard isPresented else { return }
        isPresented = false
        marquee.isActive = false
        TBPMinimizeSystemModal(bar)
        logger.info("minimized dashboard")
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
        avatarView.onTap = { [weak self] in self?.dismiss() }
        sprite.frame = NSRect(x: 3, y: 0, width: 30, height: Self.barHeight)
        avatarView.addSubview(sprite)

        bubbleView.wantsLayer = true
        bubbleView.layer?.cornerRadius = 12
        bubbleView.layer?.backgroundColor = NSColor(white: 1, alpha: 0.14).cgColor
        bubbleView.onTap = { [weak self] in self?.dismiss() }
        bubbleView.addSubview(marquee)

        chipsScroll.drawsBackground = false
        chipsScroll.hasHorizontalScroller = false
        chipsScroll.hasVerticalScroller = false
        chipsScroll.horizontalScrollElasticity = .allowed
        chipsScroll.verticalScrollElasticity = .none

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
        marquee.text = text
        let width = min(MarqueeLabel.measure(text) + 24, Self.bubbleMaxWidth)
        bubbleWidth = width
        bubbleView.fixedSize = NSSize(width: width, height: Self.barHeight)
        bubbleView.frame = NSRect(x: 0, y: 0, width: width, height: Self.barHeight)
        bubbleView.invalidateIntrinsicContentSize()
        marquee.frame = NSRect(x: 12, y: 0, width: width - 24, height: Self.barHeight)
    }

    private func layoutChips(now: Date, focusID: String?) {
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
    }

    private func makeChip(for session: SessionRecord, now: Date, focused: Bool) -> NSView {
        let title = chipTitle(session.projectName)
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .white
        label.sizeToFit()
        let labelHeight = label.frame.height
        let width = 10 + 8 + 6 + ceil(label.frame.width) + 10

        let chip = TapView()
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

        chip.onTap = { [weak self] in self?.onChipTap(session) }
        return chip
    }
}
