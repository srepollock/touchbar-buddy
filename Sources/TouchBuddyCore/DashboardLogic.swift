import Foundation

public struct SpeechKey: Equatable, Sendable {
    public let sessionID: String
    public let state: SessionState
    public let updatedAt: Date
}

public func speechKey(for session: SessionRecord?) -> SpeechKey? {
    session.map { SpeechKey(sessionID: $0.sessionID, state: $0.state, updatedAt: $0.updatedAt) }
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
    pause: TimeInterval = 1
) -> Double {
    guard cycleLength > 0, speed > 0 else { return 0 }
    let period = pause + cycleLength / speed
    let t = elapsed.truncatingRemainder(dividingBy: period)
    return t < pause ? 0 : (t - pause) * speed
}
