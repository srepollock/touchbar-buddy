import CoreGraphics
import Foundation

public enum ChattyInterval: Int, CaseIterable, Sendable {
    case five = 5
    case fifteen = 15
    case thirty = 30
}

/// Interval in minutes with +/-30% jitter; `random` is in 0..<1.
public func nextAmbientDelay(interval: ChattyInterval, random: Double) -> TimeInterval {
    Double(interval.rawValue) * 60 * (0.7 + 0.6 * random)
}

public func ambientCandidate(
    sessions: [SessionRecord],
    now: Date,
    dashboardOpen: Bool,
    pick: ([SessionRecord]) -> SessionRecord?
) -> SessionRecord? {
    guard !dashboardOpen else { return nil }
    let states = sessions.map { effectiveState($0, now: now) }
    guard !states.contains(.needsInput) else { return nil }
    let working = zip(sessions, states).filter { $0.1 == .working }.map(\.0)
    guard !working.isEmpty else { return nil }
    return pick(working)
}

/// Walks left to right in the first half of `duration` and back in the second; facing left on the return leg.
public func strollPosition(
    elapsed: TimeInterval, duration: TimeInterval, laneWidth: CGFloat, spriteWidth: CGFloat
) -> (x: CGFloat, facingLeft: Bool) {
    let maxX = max(0, laneWidth - spriteWidth)
    guard duration > 0 else { return (0, false) }
    let progress = min(max(elapsed / duration, 0), 1)
    let facingLeft = progress >= 0.5
    let leg = facingLeft ? 2 - 2 * progress : 2 * progress
    return (min(max(CGFloat(leg) * maxX, 0), maxX), facingLeft)
}

/// Session the avatar talks about when tapped: prefer working, then needs input, then finished.
public func chatterTarget(
    sessions: [SessionRecord], now: Date, pick: ([SessionRecord]) -> SessionRecord?
) -> SessionRecord? {
    for state in [SessionState.working, .needsInput, .finished] {
        let matching = sessions.filter { effectiveState($0, now: now) == state }
        if !matching.isEmpty { return pick(matching) }
    }
    return nil
}
