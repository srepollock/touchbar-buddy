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

/// Re-validates `uniqueID` itself; an invalid one yields a script that does nothing.
public func itermSelectScript(uniqueID: String) -> String {
    guard isValidITermUUID(uniqueID) else { return noOpITermScript }
    return """
    if application "iTerm2" is running then
        with timeout of 3 seconds
            tell application "iTerm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if unique id of s is "\(uniqueID)" then
                                set miniaturized of w to false
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
        end timeout
    end if
    return "missing"
    """
}

let noOpITermScript = "return \"missing\""
