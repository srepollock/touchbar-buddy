import Foundation

public struct SpeechKey: Equatable, Sendable {
    public let sessionID: String
    public let state: SessionState
    public let prompt: PromptIdentity
    /// nil while needs-input so a same-prompt rewrite does not re-pick; other states re-pick on every new record.
    public let updatedAt: Date?
}

public func speechKey(for session: SessionRecord?, now: Date) -> SpeechKey? {
    session.map { record in
        // Parallel tool calls change only the in-flight set; they must not re-pick the line of a waiting prompt.
        var spoken = record
        spoken.inFlightToolUseIDs = nil
        return SpeechKey(
            sessionID: record.sessionID, state: effectiveState(record, now: now), prompt: PromptIdentity(spoken),
            updatedAt: record.state == .needsInput ? nil : record.updatedAt
        )
    }
}

public func shouldRepickSpeech(previous: SpeechKey?, current: SpeechKey?, hasLine: Bool) -> Bool {
    !hasLine || previous != current
}

public func stripEmoji(_ text: String) -> String {
    let kept = text.unicodeScalars.filter { scalar in
        let props = scalar.properties
        if props.isEmojiPresentation || props.isEmojiModifier { return false }
        if props.isEmoji && scalar.value > 0x7F { return false }
        switch scalar.value {
        case 0x200D, 0xFE0F, 0x20E3: return false
        default: return true
        }
    }
    var scalars = String.UnicodeScalarView()
    scalars.append(contentsOf: kept)
    return String(scalars)
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespaces)
}

public func marqueeOffset(
    elapsed: TimeInterval,
    cycleLength: Double,
    speed: Double = 30,
    pause: TimeInterval = 1,
    endPause: TimeInterval = 0
) -> Double {
    guard cycleLength > 0, speed > 0 else { return 0 }
    let period = pause + cycleLength / speed + endPause
    let t = elapsed.truncatingRemainder(dividingBy: period)
    return t < pause ? 0 : min((t - pause) * speed, cycleLength)
}

public func marqueeElapsed(
    forOffset offset: Double,
    speed: Double = 30,
    pause: TimeInterval = 1
) -> TimeInterval {
    guard speed > 0 else { return 0 }
    return pause + max(0, offset) / speed
}
