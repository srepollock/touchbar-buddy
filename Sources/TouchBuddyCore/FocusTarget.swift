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

/// Shared iTerm script builder. Collections are dereferenced up front (`get`) because lazy index-based references
/// go stale mid-loop ("item 8 of every tab of item 2 of every window"). Only per-window ENUMERATION is wrapped in
/// `try`, so one odd window cannot abort the search; timeouts (-1712) and user cancel (-128) are rethrown, and the
/// last swallowed error number is returned as "missing:<n>". `body` runs outside the `try` with `w`, `t`, `s` bound
/// to the match, so its errors surface instead of reading as "missing"; it must end in a `return`.
/// Returns a no-op script unless `uniqueID` is a valid UUID.
func itermSessionScript(uniqueID: String, prelude: String = "", body: String) -> String {
    guard isValidITermUUID(uniqueID) else { return noOpITermScript }
    let indentedBody = body.split(separator: "\n", omittingEmptySubsequences: false)
        .map { $0.isEmpty ? "" : "            " + $0 }
        .joined(separator: "\n")
    return """
    \(prelude)
    set lastErr to 0
    if application "iTerm2" is running then
        with timeout of 5 seconds
            tell application "iTerm2"
                set found to false
                repeat with w in (get windows)
                    try
                        repeat with t in (get tabs of w)
                            repeat with s in (get sessions of t)
                                if unique id of s is "\(uniqueID)" then
                                    set foundW to w
                                    set foundT to t
                                    set foundS to s
                                    set found to true
                                    exit repeat
                                end if
                            end repeat
                            if found then exit repeat
                        end repeat
                    on error errMsg number errNum
                        if errNum is -1712 or errNum is -128 then error errMsg number errNum
                        set lastErr to errNum
                    end try
                    if found then exit repeat
                end repeat
                if found then
                    set w to foundW
                    set t to foundT
                    set s to foundS
    \(indentedBody)
                end if
            end tell
        end timeout
    end if
    if lastErr is 0 then return "missing"
    return "missing:" & lastErr
    """
}

/// Re-validates `uniqueID` itself; an invalid one yields a script that does nothing.
public func itermSelectScript(uniqueID: String) -> String {
    itermSessionScript(uniqueID: uniqueID, body: """
    set isHotkey to false
    try
        set isHotkey to is hotkey window of w
    on error m number n
        if n is -1712 or n is -128 then error m number n
    end try
    if isHotkey then reveal hotkey window w
    try
        set miniaturized of w to false
    on error m number n
        if n is -1712 or n is -128 then error m number n
    end try
    select w
    select t
    select s
    if not isHotkey then activate
    return "found"
    """)
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
                on error m number n
                    if n is -1712 or n is -128 then error m number n
                end try
            end repeat
        end tell
    end timeout
end if
return "none"
"""

let noOpITermScript = "return \"missing\""
