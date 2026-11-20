import AppKit
import TouchBuddyCore

@MainActor
final class MarqueeLabel: NSScrollView {
    static let font = NSFont.systemFont(ofSize: 13, weight: .medium)
    private static let frameInterval: TimeInterval = 1.0 / 30
    private static let userPause: TimeInterval = 3
    private static let tapQuietPeriod: TimeInterval = 0.4

    var onUserScroll: () -> Void = {}

    var text: String = "" {
        didSet {
            guard text != oldValue else { return }
            textWidth = Self.measure(text)
            field.stringValue = text
            relayout()
        }
    }

    var isActive = true {
        didSet { updateTimer() }
    }

    private(set) var textWidth: CGFloat = 0
    private let field = NSTextField(labelWithString: "")
    private let document = NSView()
    private var timer: Timer?
    private var startedAt = Date()
    private var pausedUntil = Date.distantPast
    private var resyncPending = false
    private var isProgrammaticScroll = false
    private var lastOffset: CGFloat = 0
    private var isLiveScrolling = false
    private var lastUserScrollAt = Date.distantPast

    /// True while the user is dragging the bubble or just finished; taps are ignored then.
    var isUserScrolling: Bool {
        isLiveScrolling || Date().timeIntervalSince(lastUserScrollAt) < Self.tapQuietPeriod
    }

    static func measure(_ text: String) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        drawsBackground = false
        hasHorizontalScroller = false
        hasVerticalScroller = false
        horizontalScrollElasticity = .allowed
        verticalScrollElasticity = .none

        field.font = Self.font
        field.textColor = .white
        field.lineBreakMode = .byClipping
        field.maximumNumberOfLines = 1
        document.addSubview(field)
        documentView = document

        contentView.postsBoundsChangedNotifications = true
        let center = NotificationCenter.default
        center.addObserver(
            self, selector: #selector(boundsChanged), name: NSView.boundsDidChangeNotification, object: contentView
        )
        for name in [
            NSScrollView.willStartLiveScrollNotification,
            NSScrollView.didLiveScrollNotification,
            NSScrollView.didEndLiveScrollNotification,
        ] {
            center.addObserver(self, selector: #selector(userScrolled), name: name, object: self)
        }
        center.addObserver(
            self, selector: #selector(liveScrollStarted), name: NSScrollView.willStartLiveScrollNotification,
            object: self
        )
        center.addObserver(
            self, selector: #selector(liveScrollEnded), name: NSScrollView.didEndLiveScrollNotification,
            object: self
        )
    }

    required init?(coder: NSCoder) { nil }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        relayout()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateTimer()
    }

    override func viewDidHide() {
        super.viewDidHide()
        updateTimer()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        updateTimer()
    }

    private var scrolls: Bool { textWidth + 2 > bounds.width && bounds.width > 0 }
    private var maxOffset: CGFloat { max(0, document.frame.width - bounds.width) }

    @objc private func boundsChanged() {
        guard !isProgrammaticScroll, abs(contentView.bounds.origin.x - lastOffset) > 0.5 else { return }
        userScrolled()
    }

    @objc private func liveScrollStarted() { isLiveScrolling = true }

    @objc private func liveScrollEnded() { isLiveScrolling = false }

    @objc private func userScrolled() {
        lastUserScrollAt = Date()
        pausedUntil = Date().addingTimeInterval(Self.userPause)
        resyncPending = true
        onUserScroll()
    }

    private func setOffset(_ x: CGFloat) {
        lastOffset = x
        isProgrammaticScroll = true
        contentView.scroll(to: NSPoint(x: x, y: 0))
        reflectScrolledClipView(contentView)
        isProgrammaticScroll = false
    }

    private func relayout() {
        let height = ceil(Self.font.boundingRectForFont.height)
        let docWidth = scrolls ? textWidth + 2 : max(bounds.width, 1)
        document.frame = NSRect(x: 0, y: 0, width: docWidth, height: bounds.height)
        let x = scrolls ? 0 : max(0, (bounds.width - textWidth) / 2)
        field.frame = NSRect(x: x, y: (bounds.height - height) / 2, width: textWidth + 2, height: height)
        setOffset(0)
        startedAt = Date()
        resyncPending = false
        updateTimer()
    }

    private func updateTimer() {
        let shouldRun = scrolls && isActive && window != nil && !isHiddenOrHasHiddenAncestor
        if shouldRun, timer == nil {
            startedAt = Date()
            let timer = Timer(timeInterval: Self.frameInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.step() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        } else if !shouldRun, let timer {
            timer.invalidate()
            self.timer = nil
            setOffset(0)
        }
    }

    private func step() {
        let now = Date()
        guard now >= pausedUntil else { return }
        if resyncPending {
            resyncPending = false
            startedAt = now.addingTimeInterval(-marqueeElapsed(forOffset: Double(contentView.bounds.origin.x)))
        }
        let offset = marqueeOffset(
            elapsed: now.timeIntervalSince(startedAt), cycleLength: Double(maxOffset), endPause: 1
        )
        setOffset(CGFloat(offset))
    }
}
