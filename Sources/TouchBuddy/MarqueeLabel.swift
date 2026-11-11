import AppKit
import TouchBuddyCore

@MainActor
final class MarqueeLabel: NSView {
    static let font = NSFont.systemFont(ofSize: 13, weight: .medium)
    private static let gap: CGFloat = 40
    private static let frameInterval: TimeInterval = 1.0 / 30

    var text: String = "" {
        didSet {
            guard text != oldValue else { return }
            textWidth = Self.measure(text)
            first.stringValue = text
            second.stringValue = text
            invalidateIntrinsicContentSize()
            relayout()
        }
    }

    var isActive = true {
        didSet { updateTimer() }
    }

    private(set) var textWidth: CGFloat = 0
    private let first = MarqueeLabel.makeField()
    private let second = MarqueeLabel.makeField()
    private var timer: Timer?
    private var startedAt = Date()

    private static func makeField() -> NSTextField {
        let field = NSTextField(labelWithString: "")
        field.font = font
        field.textColor = .white
        field.lineBreakMode = .byClipping
        field.maximumNumberOfLines = 1
        return field
    }

    static func measure(_ text: String) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        addSubview(first)
        addSubview(second)
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize {
        NSSize(width: textWidth, height: 30)
    }

    override func layout() {
        super.layout()
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

    private var scrolls: Bool { textWidth > bounds.width && bounds.width > 0 }

    private func fieldFrame(x: CGFloat) -> NSRect {
        let height = ceil(Self.font.boundingRectForFont.height)
        return NSRect(x: x, y: (bounds.height - height) / 2, width: textWidth + 2, height: height)
    }

    private func relayout() {
        startedAt = Date()
        if scrolls {
            first.frame = fieldFrame(x: 0)
            second.frame = fieldFrame(x: textWidth + Self.gap)
            second.isHidden = false
        } else {
            first.frame = fieldFrame(x: max(0, (bounds.width - textWidth) / 2))
            second.isHidden = true
        }
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
            if scrolls {
                first.frame = fieldFrame(x: 0)
                second.frame = fieldFrame(x: textWidth + Self.gap)
            }
        }
    }

    private func step() {
        let cycle = Double(textWidth + Self.gap)
        let offset = CGFloat(marqueeOffset(elapsed: Date().timeIntervalSince(startedAt), cycleLength: cycle))
        first.frame = fieldFrame(x: -offset)
        second.frame = fieldFrame(x: textWidth + Self.gap - offset)
    }
}
