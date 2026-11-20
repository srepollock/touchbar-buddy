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

private let maxFrameCount = 500
private let maxSourcePixels = 4096
private let maxThumbnailPixels = 256

private func decodeFrame(from source: CGImageSource, at index: Int, path: String) throws -> CGImage {
    guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int,
          let height = properties[kCGImagePropertyPixelHeight] as? Int,
          width <= maxSourcePixels, height <= maxSourcePixels
    else {
        throw CharacterError.unreadable(path)
    }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceThumbnailMaxPixelSize: maxThumbnailPixels,
        kCGImageSourceCreateThumbnailWithTransform: true,
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) else {
        throw CharacterError.unreadable(path)
    }
    return image
}

private func pngFrameDuration(fps: Double) -> TimeInterval {
    let effectiveFPS = fps.isFinite && fps > 0 ? fps : defaultFPS
    return max(1 / effectiveFPS, minimumGIFDelay)
}

public func loadFrames(_ source: AnimationSource, fps: Double) throws -> [AnimationFrame] {
    switch source {
    case .gif(let url):
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw CharacterError.unreadable(url.path)
        }
        let count = CGImageSourceGetCount(imageSource)
        guard count > 0, count <= maxFrameCount else { throw CharacterError.unreadable(url.path) }
        return try (0..<count).map { index in
            AnimationFrame(
                image: try decodeFrame(from: imageSource, at: index, path: url.path),
                duration: gifDelay(of: imageSource, at: index)
            )
        }

    case .frames(let urls):
        guard urls.count <= maxFrameCount else {
            throw CharacterError.unreadable(urls.first?.deletingLastPathComponent().path ?? "")
        }
        let duration = pngFrameDuration(fps: fps)
        return try urls.map { url in
            guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
                  CGImageSourceGetCount(imageSource) > 0
            else {
                throw CharacterError.unreadable(url.path)
            }
            return AnimationFrame(image: try decodeFrame(from: imageSource, at: 0, path: url.path), duration: duration)
        }
    }
}
