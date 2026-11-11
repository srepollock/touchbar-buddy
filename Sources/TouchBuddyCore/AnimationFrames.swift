import CoreGraphics
import Foundation
import ImageIO

public struct AnimationFrame: @unchecked Sendable {
    // CGImage is immutable, so sharing across threads is safe.
    public let image: CGImage
    public let duration: TimeInterval

    public init(image: CGImage, duration: TimeInterval) {
        self.image = image
        self.duration = duration
    }
}

private let minimumGIFDelay: TimeInterval = 0.02
private let defaultGIFDelay: TimeInterval = 0.1
private let defaultFPS: Double = 8

private func gifDelay(of source: CGImageSource, at index: Int) -> TimeInterval {
    guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
          let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any]
    else {
        return defaultGIFDelay
    }
    let delay = (gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
        ?? (gif[kCGImagePropertyGIFDelayTime] as? Double)
        ?? defaultGIFDelay
    return max(delay, minimumGIFDelay)
}

public func loadFrames(_ source: AnimationSource, fps: Double) throws -> [AnimationFrame] {
    switch source {
    case .gif(let url):
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw CharacterError.unreadable(url.path)
        }
        let count = CGImageSourceGetCount(imageSource)
        guard count > 0 else { throw CharacterError.unreadable(url.path) }
        return try (0..<count).map { index in
            guard let image = CGImageSourceCreateImageAtIndex(imageSource, index, nil) else {
                throw CharacterError.unreadable(url.path)
            }
            return AnimationFrame(image: image, duration: gifDelay(of: imageSource, at: index))
        }

    case .frames(let urls):
        let effectiveFPS = fps > 0 ? fps : defaultFPS
        let duration = 1 / effectiveFPS
        return try urls.map { url in
            guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
            else {
                throw CharacterError.unreadable(url.path)
            }
            return AnimationFrame(image: image, duration: duration)
        }
    }
}
