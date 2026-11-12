import Foundation

public enum QuickReply: Equatable, Sendable {
    case allow
    case allowAlways
    case deny
    case choose(index: Int, label: String)
}

public func quickReplies(for r: SessionRecord) -> [QuickReply] {
    guard r.state == .needsInput,
          let id = r.itermSessionID, itermUniqueID(from: id) != nil
    else { return [] }
    switch r.speechKind {
    case .permission:
        return [.allow, .allowAlways, .deny]
    case .question:
        guard let options = r.pendingOptions, !options.isEmpty else { return [] }
        return options.enumerated().map { .choose(index: $0.offset + 1, label: $0.element) }
    default:
        return []
    }
}

public func keystrokes(for reply: QuickReply) -> String {
    switch reply {
    case .allow: return "1"
    case .allowAlways: return "2"
    case .deny: return "\u{1B}"
    case .choose(let index, _): return (1...9).contains(index) ? String(index) : ""
    }
}

public func isReplyStillValid(shownFor: SessionRecord, current: SessionRecord?) -> Bool {
    guard let current else { return false }
    return current.state == .needsInput && current.updatedAt == shownFor.updatedAt
}

/// true = affirmative, false = negative, nil = neither. Matches the word at the start of the label.
public func yesNoPolarity(_ label: String) -> Bool? {
    let trimmed = label.trimmingCharacters(in: .whitespaces)
    if trimmed.prefixMatch(of: /(?i)yes(?![0-9A-Za-z])/) != nil { return true }
    if trimmed.prefixMatch(of: /(?i)no(?![0-9A-Za-z])/) != nil { return false }
    return nil
}

public func isYesNo(_ options: [String]) -> Bool {
    guard options.count == 2 else { return false }
    let polarities = options.map(yesNoPolarity)
    return polarities.contains(true) && polarities.contains(false)
}

/// Only the UUID and whitelisted keystrokes (a single digit 1-9, or Esc) are ever embedded.
public func itermWriteScript(uniqueID: String, keystrokes: String) -> String {
    guard isValidITermUUID(uniqueID), let literal = appleScriptKeyLiteral(keystrokes) else {
        return noOpITermScript
    }
    return """
    if application "iTerm2" is running then
        with timeout of 3 seconds
            tell application "iTerm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if unique id of s is "\(uniqueID)" then
                                tell s to write text \(literal) newline NO
                                return "sent"
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
        end timeout
    end if
    return "missing"
    """
}

private func appleScriptKeyLiteral(_ keys: String) -> String? {
    if keys == "\u{1B}" { return "(character id 27)" }
    guard keys.count == 1, let digit = keys.first, ("1"..."9").contains(digit) else { return nil }
    return "\"\(keys)\""
}
