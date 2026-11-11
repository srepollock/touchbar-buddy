import Foundation

public let finishedDecaySeconds: TimeInterval = 600
public let staleNoPIDSeconds: TimeInterval = 86_400

public func effectiveState(_ r: SessionRecord, now: Date) -> SessionState {
    if r.state == .finished, now.timeIntervalSince(r.updatedAt) > finishedDecaySeconds {
        return .idle
    }
    return r.state
}

public func statePriority(_ s: SessionState) -> Int {
    switch s {
    case .needsInput: 0
    case .working: 1
    case .finished: 2
    case .idle: 3
    }
}

public func orderedForDisplay(_ rs: [SessionRecord], now: Date) -> [SessionRecord] {
    rs.sorted { a, b in
        let pa = statePriority(effectiveState(a, now: now))
        let pb = statePriority(effectiveState(b, now: now))
        if pa != pb { return pa < pb }
        if a.updatedAt != b.updatedAt { return a.updatedAt > b.updatedAt }
        return a.sessionID < b.sessionID
    }
}

public func overallState(_ rs: [SessionRecord], now: Date) -> SessionState? {
    rs.map { effectiveState($0, now: now) }.min { statePriority($0) < statePriority($1) }
}

public func popupTriggers(old: [SessionRecord], new: [SessionRecord], now: Date) -> [SessionRecord] {
    let oldByID = Dictionary(old.map { ($0.sessionID, $0) }, uniquingKeysWith: { _, last in last })
    return new.filter { record in
        guard effectiveState(record, now: now) == .needsInput else { return false }
        guard let previous = oldByID[record.sessionID] else { return true }
        return effectiveState(previous, now: now) != .needsInput
            || previous.updatedAt != record.updatedAt
    }
}

public func partitionDead(
    _ rs: [SessionRecord],
    now: Date,
    isAlive: (Int32) -> Bool
) -> (alive: [SessionRecord], deadIDs: [String]) {
    var alive: [SessionRecord] = []
    var deadIDs: [String] = []
    for r in rs {
        let isDead: Bool
        if let pid = r.claudePID {
            isDead = !isAlive(pid)
        } else {
            isDead = now.timeIntervalSince(r.updatedAt) > staleNoPIDSeconds
        }
        if isDead { deadIDs.append(r.sessionID) } else { alive.append(r) }
    }
    return (alive, deadIDs)
}

public func chipTitle(_ projectName: String, maxChars: Int = 18) -> String {
    guard maxChars > 0 else { return "" }
    guard projectName.count > maxChars else { return projectName }
    return String(projectName.prefix(maxChars - 1)) + "…"
}
