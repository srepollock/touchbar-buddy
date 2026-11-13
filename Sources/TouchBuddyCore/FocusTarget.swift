import Foundation

public enum FocusTarget: Equatable, Sendable {
    case itermSession(uniqueID: String)
    case claudeDesktop
    case itermApp
}

public func itermUniqueID(from itermSessionID: String) -> String? {
    let pattern = /w[0-9]+t[0-9]+p[0-9]+:([0-9A-Fa-f-]{36})/
    guard let match = itermSessionID.wholeMatch(of: pattern) else { return nil }
    return String(match.1)
}

public func focusTarget(for r: SessionRecord) -> FocusTarget {
    if let id = r.itermSessionID, let uniqueID = itermUniqueID(from: id) {
        return .itermSession(uniqueID: uniqueID)
    }
    if r.entrypoint?.localizedCaseInsensitiveContains("desktop") == true {
        return .claudeDesktop
    }
    return .itermApp
}

public func isValidITermUUID(_ value: String) -> Bool {
    let scalars = value.unicodeScalars
    return scalars.count == 36 && scalars.allSatisfy { scalar in
        switch scalar.value {
        case 0x30...0x39, 0x41...0x46, 0x61...0x66, 0x2D: return true
        default: return false
        }
    }
}

/// Shared session lookup for iTerm scripts. Collections are dereferenced up front (`get`) because lazy
/// index-based references go stale mid-loop ("item 8 of every tab of item 2 of every window"), and each window
/// is wrapped in `try` so one odd window cannot abort the search. `body` runs with `w`, `t`, `s` bound to the match
/// and must end in a `return`.
func itermSessionLookup(uniqueID: String, body: String) -> String {
    let indented = body.split(separator: "\n", omittingEmptySubsequences: false)
        .map { $0.isEmpty ? "" : "                    " + $0 }
        .joined(separator: "\n")
    return """
                repeat with w in (get windows)
                    try
                        repeat with t in (get tabs of w)
                            repeat with s in (get sessions of t)
                                if unique id of s is "\(uniqueID)" then
    \(indented)
                                end if
                            end repeat
                        end repeat
                    end try
                end repeat
    """
}

/// Re-validates `uniqueID` itself; an invalid one yields a script that does nothing.
public func itermSelectScript(uniqueID: String) -> String {
    guard isValidITermUUID(uniqueID) else { return noOpITermScript }
    let lookup = itermSessionLookup(uniqueID: uniqueID, body: """
    set isHotkey to false
    try
        set isHotkey to is hotkey window of w
    end try
    if isHotkey then reveal hotkey window w
    try
        set miniaturized of w to false
    end try
    select w
    select t
    select s
    if not isHotkey then activate
    return "found"
    """)
    return """
    if application "iTerm2" is running then
        with timeout of 5 seconds
            tell application "iTerm2"
    \(lookup)
            end tell
        end timeout
    end if
    return "missing"
    """
}

/// Fallback when the session cannot be found: reveals a hotkey window if one exists. Never activates iTerm
/// and never creates a window or tab.
public let itermRevealHotkeyScript = """
if application "iTerm2" is running then
    with timeout of 5 seconds
        tell application "iTerm2"
            repeat with w in (get windows)
                try
                    if is hotkey window of w then
                        reveal hotkey window w
                        return "revealed"
                    end if
                end try
            end repeat
        end tell
    end timeout
end if
return "none"
"""

let noOpITermScript = "return \"missing\""
