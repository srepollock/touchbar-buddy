import AppKit
import TouchBuddyCore

@MainActor
final class SpriteView: NSView {
    private var frames: [AnimationFrame] = []
    private var index = 0
    private var timer: Timer?
    private var currentKey: String?
    private var onceCompletion: (() -> Void)?
    private let contentLayer = CALayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        contentLayer.contentsGravity = .resizeAspect
        contentLayer.magnificationFilter = .nearest
        layer?.addSublayer(contentLayer)
        layoutContentLayer()
    }

    override func layout() {
        super.layout()
        layoutContentLayer()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutContentLayer()
    }

    private func layoutContentLayer() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentLayer.bounds = NSRect(origin: .zero, size: bounds.size)
        contentLayer.position = NSPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()
    }

    /// Mirrors the sprite horizontally via a layer transform (used while walking left).
    var facingLeft = false {
        didSet {
            guard facingLeft != oldValue else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            contentLayer.setAffineTransform(facingLeft ? CGAffineTransform(scaleX: -1, y: 1) : .identity)
            CATransaction.commit()
        }
    }

    /// Back-and-forth pacing by +/- `amplitude` points, driven by Core Animation (no timer).
    func startPacing(amplitude: CGFloat) {
        guard contentLayer.animation(forKey: "pace") == nil else { return }
        let animation = CABasicAnimation(keyPath: "position.x")
        animation.fromValue = -amplitude
        animation.toValue = amplitude
        animation.isAdditive = true
        animation.duration = 1.4
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        contentLayer.add(animation, forKey: "pace")
    }

    func stopPacing() {
        contentLayer.removeAnimation(forKey: "pace")
    }

    /// Plays `onceFrames` one time, then runs `completion` (the caller restores the state animation).
    func playOnce(_ onceFrames: [AnimationFrame], completion: @escaping () -> Void) {
        timer?.invalidate()
        currentKey = nil
        frames = onceFrames
        index = 0
        onceCompletion = completion
        showCurrent()
        scheduleNext()
    }

    required init?(coder: NSCoder) { nil }

    func play(_ newFrames: [AnimationFrame], key: String) {
        guard key != currentKey else { return }
        currentKey = key
        timer?.invalidate()
        onceCompletion = nil
        frames = newFrames
        index = 0
        showCurrent()
        scheduleNext()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        frames = []
        currentKey = nil
        onceCompletion = nil
        stopPacing()
        facingLeft = false
        contentLayer.contents = nil
    }

    private func showCurrent() {
        guard frames.indices.contains(index) else {
            contentLayer.contents = nil
            return
        }
        contentLayer.contents = frames[index].image
    }

    private func scheduleNext() {
        guard frames.count > 1 else {
            finishOnce()
            return
        }
        let delay = frames[index].duration
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.onceCompletion != nil, self.index == self.frames.count - 1 {
                    self.finishOnce()
                    return
                }
                self.index = (self.index + 1) % self.frames.count
                self.showCurrent()
                self.scheduleNext()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func finishOnce() {
        guard let completion = onceCompletion else { return }
        onceCompletion = nil
        completion()
    }
}
