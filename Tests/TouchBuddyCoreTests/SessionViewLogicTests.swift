import Foundation
import Testing
@testable import TouchBuddyCore

private let base = Date(timeIntervalSince1970: 1_000_000)

private func rec(
    _ id: String,
    _ state: SessionState,
    updated: Date = base,
    pid: Int32? = nil,
    name: String = "proj"
) -> SessionRecord {
    SessionRecord(
        sessionID: id,
        cwd: "/x/\(name)",
        projectName: name,
        state: state,
        speechKind: .idle,
        updatedAt: updated,
        startedAt: base,
        claudePID: pid
    )
}

@Test func finishedDecaysToIdleAfter600s() {
    let r = rec("a", .finished)
    #expect(effectiveState(r, now: base.addingTimeInterval(599)) == .finished)
    #expect(effectiveState(r, now: base.addingTimeInterval(601)) == .idle)
}

@Test func nonFinishedStatesDoNotDecay() {
    let later = base.addingTimeInterval(10_000)
    #expect(effectiveState(rec("a", .working), now: later) == .working)
    #expect(effectiveState(rec("a", .needsInput), now: later) == .needsInput)
}

@Test func orderingIsUrgencyThenRecency() {
    let rs = [
        rec("idle", .idle, updated: base.addingTimeInterval(50)),
        rec("workOld", .working, updated: base.addingTimeInterval(10)),
        rec("workNew", .working, updated: base.addingTimeInterval(20)),
        rec("needs", .needsInput, updated: base),
        rec("fin", .finished, updated: base.addingTimeInterval(30)),
    ]
    let ids = orderedForDisplay(rs, now: base.addingTimeInterval(60)).map(\.sessionID)
    #expect(ids == ["needs", "workNew", "workOld", "fin", "idle"])
}

@Test func overallIsMostUrgent() {
    let rs = [rec("a", .idle), rec("b", .working), rec("c", .finished)]
    #expect(overallState(rs, now: base) == .working)
}

@Test func overallNilWhenEmpty() {
    #expect(overallState([], now: base) == nil)
}

@Test func popupOnTransitionIntoNeedsInput() {
    let old = [rec("a", .working)]
    let new = [rec("a", .needsInput, updated: base.addingTimeInterval(5))]
    #expect(popupTriggers(old: old, new: new, now: base.addingTimeInterval(5)).map(\.sessionID) == ["a"])
}

@Test func popupForNewSessionAbsentFromOld() {
    let new = [rec("a", .needsInput)]
    #expect(popupTriggers(old: [], new: new, now: base).map(\.sessionID) == ["a"])
}

@Test func noPopupWhenStillNeedsInputUnchanged() {
    let r = rec("a", .needsInput)
    #expect(popupTriggers(old: [r], new: [r], now: base).isEmpty)
}

@Test func popupOnRepeatedPermissionPrompt() {
    var first = rec("a", .needsInput)
    first.detail = "ls"
    var second = rec("a", .needsInput, updated: base.addingTimeInterval(30))
    second.detail = "rm -rf build"
    #expect(popupTriggers(old: [first], new: [second], now: base.addingTimeInterval(30)).count == 1)
    second.detail = first.detail
    second.pendingToolUseID = "toolu_2"
    #expect(popupTriggers(old: [first], new: [second], now: base.addingTimeInterval(30)).count == 1)
}

@Test func noPopupWhenSamePromptRewrittenLater() {
    var first = rec("a", .needsInput)
    first.pendingToolUseID = "toolu_1"
    first.toolName = "Bash"
    first.detail = "ls"
    var second = first
    second.updatedAt = base.addingTimeInterval(1)
    #expect(popupTriggers(old: [first], new: [second], now: base.addingTimeInterval(1)).isEmpty)
}

@Test func noPopupForFinished() {
    let old = [rec("a", .working)]
    let new = [rec("a", .finished, updated: base.addingTimeInterval(5))]
    #expect(popupTriggers(old: old, new: new, now: base.addingTimeInterval(5)).isEmpty)
}

@Test func deadPIDPartitioned() {
    let rs = [rec("live", .working, pid: 1), rec("dead", .working, pid: 2)]
    let result = partitionDead(rs, now: base) { $0 == 1 }
    #expect(result.alive.map(\.sessionID) == ["live"])
    #expect(result.deadIDs == ["dead"])
}

@Test func noPIDStaleAfter24h() {
    let rs = [rec("fresh", .idle), rec("stale", .idle, updated: base.addingTimeInterval(-90_000))]
    let result = partitionDead(rs, now: base) { _ in true }
    #expect(result.alive.map(\.sessionID) == ["fresh"])
    #expect(result.deadIDs == ["stale"])
}

@Test func chipTitleTruncates() {
    let long = String(repeating: "a", count: 60)
    let title = chipTitle(long)
    #expect(title.count == 18)
    #expect(title.hasSuffix("…"))
    #expect(title == String(repeating: "a", count: 17) + "…")
    #expect(chipTitle("short") == "short")
    #expect(chipTitle(String(repeating: "b", count: 18)).count == 18)
}

@Test func orderingHandlesTwelveSessions() {
    let states: [SessionState] = [.idle, .finished, .working, .needsInput]
    let rs = (0..<12).map { i in
        rec("s\(i)", states[i % 4], updated: base.addingTimeInterval(Double(i)))
    }
    let ordered = orderedForDisplay(rs, now: base.addingTimeInterval(20))
    #expect(ordered.count == 12)
    let priorities = ordered.map { statePriority(effectiveState($0, now: base.addingTimeInterval(20))) }
    #expect(priorities == priorities.sorted())
    #expect(ordered.first?.state == .needsInput)
}

@Test func statusHexMatchesSpec() {
    #expect(statusHex(.needsInput) == 0xF5A623)
    #expect(statusHex(.working) == 0x4A90E2)
    #expect(statusHex(.finished) == 0x7ED321)
    #expect(statusHex(.idle) == 0x666666)
    #expect(statusHex(nil) == 0x666666)
}

@Test func displaySignatureChangesOnDecayAndOrder() {
    let rs = [rec("a", .finished), rec("b", .working)]
    let early = displaySignature(rs, now: base.addingTimeInterval(10))
    let late = displaySignature(rs, now: base.addingTimeInterval(700))
    #expect(early != late)
    #expect(displaySignature(rs, now: base.addingTimeInterval(11)) == early)
    #expect(displaySignature(rs.reversed(), now: base.addingTimeInterval(10)) != early)
}
