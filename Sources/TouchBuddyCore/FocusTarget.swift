import Foundation

public enum FocusTarget: Equatable, Sendable {
    case itermSession(uniqueID: String)
    case claudeDesktop
    case itermApp
}

public func itermUniqueID(from itermSessionID: String) -> String? {
    let pattern = /w\d+t\d+p\d+:([0-9A-Fa-f-]{36})/
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

/// `uniqueID` must come from `itermUniqueID(from:)`; it is the only value ever embedded.
public func itermSelectScript(uniqueID: String) -> String {
    """
    tell application "iTerm2"
        repeat with w in windows
            repeat with t in tabs of w
                repeat with s in sessions of t
                    if unique id of s is "\(uniqueID)" then
                        select w
                        select t
                        select s
                        activate
                        return "found"
                    end if
                end repeat
            end repeat
        end repeat
    end tell
    return "missing"
    """
}
