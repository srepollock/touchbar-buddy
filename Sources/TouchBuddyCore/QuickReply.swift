import Foundation

public enum QuickReply: Equatable, Sendable {
    case allow
    case allowAlways
    case deny
    case choose(index: Int, label: String)
}

/// Permission prompts whose on-screen layout was verified against live Claude Code (see task-12 report).
private let verifiedPermissionTools: Set<String> = ["Bash", "Edit"]

public func quickReplies(for r: SessionRecord) -> [QuickReply] {
    // With several tool calls in flight the prompt on screen may not be the one recorded, unless a
    // PermissionRequest named it.
    let unambiguous = (r.inFlightToolUseIDs?.count ?? 0) <= 1 || r.permissionRequestConfirmed == true
    guard r.state == .needsInput, r.pendingToolUseID != nil, unambiguous,
          let id = r.itermSessionID, itermUniqueID(from: id) != nil
    else { return [] }
    switch r.speechKind {
    case .permission:
        switch r.toolName {
        case "Bash": return [.allow, .allowAlways, .deny]
        case "Edit": return [.allow, .deny]
        default: return []
        }
    case .question:
        guard let options = r.pendingOptions, !options.isEmpty else { return [] }
        return options.prefix(9).enumerated().map { .choose(index: $0.offset + 1, label: $0.element) }
    default:
        return []
    }
}

/// Exact footer lines Claude Code shows only while a prompt waits for a key. The script matches them against the
/// last 3 non-empty lines of the screen only (a trimmed line that ends with the permission footer or starts with
/// the question footer), so the same text in transcript or tool output does not count.
public let permissionPromptFooter = "Esc to cancel · Tab to amend"
public let questionPromptFooter = "Enter to select ·"
public let knownPromptFooters = [permissionPromptFooter, questionPromptFooter]

public func promptFooters(for reply: QuickReply) -> [String] {
    switch reply {
    case .allow, .allowAlways, .deny: return [permissionPromptFooter]
    case .choose: return [questionPromptFooter]
    }
}

/// Taps right after the buttons were (re)built are ignored so a rebuild cannot retarget a finger already in flight.
public func isReplyTapAccepted(builtAt: Date, now: Date, settle: TimeInterval = 0.5) -> Bool {
    now.timeIntervalSince(builtAt) >= settle
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
    return current.state == .needsInput && current == shownFor
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

/// Only the UUID, whitelisted keystrokes (a single digit 1-9, or Esc) and known footer constants are ever embedded.
/// The script types only if one of the last 3 non-empty screen lines has the footer shape; hook data never enters it.
public func itermWriteScript(
    uniqueID: String, keystrokes: String, footers: [String] = knownPromptFooters
) -> String {
    let known = footers.filter { knownPromptFooters.contains($0) }
    guard isValidITermUUID(uniqueID), let literal = appleScriptKeyLiteral(keystrokes), !known.isEmpty else {
        return noOpITermScript
    }
    let condition = known.map { footer -> String in
        footer == questionPromptFooter
            ? "(trimmedLine starts with \"\(footer)\")"
            : "(trimmedLine ends with \"\(footer)\")"
    }.joined(separator: " or ")
    return """
    on trimText(t)
        set ws to {" ", tab, return, linefeed, character id 160}
        repeat while t is not "" and (first character of t) is in ws
            if (count of t) is 1 then return ""
            set t to text 2 thru -1 of t
        end repeat
        repeat while t is not "" and (last character of t) is in ws
            if (count of t) is 1 then return ""
            set t to text 1 thru -2 of t
        end repeat
        return t
    end trimText

    if application "iTerm2" is running then
        with timeout of 3 seconds
            tell application "iTerm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if unique id of s is "\(uniqueID)" then
                                tell s to set screenText to contents
                                set screenLines to paragraphs of screenText
                                set promptShown to false
                                set seen to 0
                                repeat with i from (count of screenLines) to 1 by -1
                                    set trimmedLine to my trimText(item i of screenLines)
                                    if trimmedLine is not "" then
                                        set seen to seen + 1
                                        if \(condition) then set promptShown to true
                                        if seen is greater than or equal to 3 then exit repeat
                                    end if
                                end repeat
                                if promptShown then
                                    tell s to write text \(literal) newline NO
                                    return "sent"
                                end if
                                return "noprompt"
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
    let scalars = Array(keys.unicodeScalars)
    guard scalars.count == 1, let scalar = scalars.first else { return nil }
    switch scalar.value {
    case 0x1B: return "(character id 27)"
    case 0x31...0x39: return "\"\(Character(scalar))\""
    default: return nil
    }
}
