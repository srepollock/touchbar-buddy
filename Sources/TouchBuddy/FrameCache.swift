import Foundation
import OSLog
import TouchBuddyCore

private let logger = Logger(subsystem: "ca.spollock.touchbuddy", category: "frames")

@MainActor
final class FrameCache {
    private var cache: [String: [AnimationFrame]] = [:]
    private var failedKeys: Set<String> = []

    func frames(
        for descriptor: CharacterDescriptor, state: SessionState
    ) -> (key: String, frames: [AnimationFrame])? {
        let key = "\(descriptor.id)|\(state.rawValue)"
        if let cached = cache[key] { return (key, cached) }
        if failedKeys.contains(key) { return nil }
        do {
            let decoded = try loadFrames(descriptor.animation(for: state), fps: descriptor.manifest.fps ?? 8)
            guard !decoded.isEmpty else { throw CharacterError.unreadable(descriptor.id) }
            cache[key] = decoded
            return (key, decoded)
        } catch {
            logger.error("frame decode failed for \(key, privacy: .public): \(String(describing: error), privacy: .public)")
            failedKeys.insert(key)
            return nil
        }
    }

    func resolve(
        character: CharacterDescriptor?, fallback: CharacterDescriptor?, state: SessionState
    ) -> (key: String, frames: [AnimationFrame])? {
        character.flatMap { frames(for: $0, state: state) }
            ?? fallback.flatMap { $0.id == character?.id ? nil : frames(for: $0, state: state) }
    }
}
