import AppKit
import TouchBuddyCore

@MainActor
final class SpriteView: NSView {
    private var frames: [AnimationFrame] = []
    private var index = 0
    private var timer: Timer?
    private var currentKey: String?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.contentsGravity = .resizeAspect
        layer?.magnificationFilter = .nearest
    }

    required init?(coder: NSCoder) { nil }

    func play(_ newFrames: [AnimationFrame], key: String) {
        guard key != currentKey else { return }
        currentKey = key
        timer?.invalidate()
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
        layer?.contents = nil
    }

    private func showCurrent() {
        guard frames.indices.contains(index) else {
            layer?.contents = nil
            return
        }
        layer?.contents = frames[index].image
    }

    private func scheduleNext() {
        guard frames.count > 1 else { return }
        let delay = frames[index].duration
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.index = (self.index + 1) % self.frames.count
                self.showCurrent()
                self.scheduleNext()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
