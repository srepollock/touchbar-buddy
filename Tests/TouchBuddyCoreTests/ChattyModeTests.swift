import CoreGraphics
import Foundation
import Testing
@testable import TouchBuddyCore

private let base = Date(timeIntervalSince1970: 1_000_000)

private func rec(_ id: String, _ state: SessionState) -> SessionRecord {
    SessionRecord(
        sessionID: id, cwd: "/x/\(id)", projectName: id, state: state, speechKind: .idle,
        updatedAt: base, startedAt: base
    )
}

@Test func delayWithinJitterBounds() {
    #expect(abs(nextAmbientDelay(interval: .fifteen, random: 0) - 15 * 60 * 0.7) < 0.001)
    #expect(abs(nextAmbientDelay(interval: .fifteen, random: 0.5) - 15 * 60) < 0.001)
    let high = nextAmbientDelay(interval: .fifteen, random: 0.999)
    #expect(high > 15 * 60 * 1.29 && high < 15 * 60 * 1.3)
    #expect(abs(nextAmbientDelay(interval: .five, random: 0) - 5 * 60 * 0.7) < 0.001)
}

@Test func noCandidateWhenDashboardOpen() {
    let picked = ambientCandidate(
        sessions: [rec("a", .working)], now: base, dashboardOpen: true, pick: { $0.first }
    )
    #expect(picked == nil)
}

@Test func noCandidateWhenAnyNeedsInput() {
    let picked = ambientCandidate(
        sessions: [rec("a", .working), rec("b", .needsInput)], now: base, dashboardOpen: false, pick: { $0.first }
    )
    #expect(picked == nil)
}

@Test func noCandidateWhenNothingWorking() {
    let picked = ambientCandidate(
        sessions: [rec("a", .idle), rec("b", .finished)], now: base, dashboardOpen: false, pick: { $0.first }
    )
    #expect(picked == nil)
}

@Test func picksAmongWorkingOnly() {
    var offered: [String] = []
    let picked = ambientCandidate(
        sessions: [rec("a", .idle), rec("b", .working), rec("c", .working), rec("d", .finished)],
        now: base, dashboardOpen: false,
        pick: { offered = $0.map(\.sessionID); return $0.last }
    )
    #expect(offered == ["b", "c"])
    #expect(picked?.sessionID == "c")
}

@Test func decayedFinishedIsNotWorkingAndNeedsInputUsesEffectiveState() {
    let old = base.addingTimeInterval(-10_000)
    var finished = rec("f", .finished)
    finished.updatedAt = old
    let picked = ambientCandidate(sessions: [finished], now: base, dashboardOpen: false, pick: { $0.first })
    #expect(picked == nil)
}

@Test func strollGoesThereAndBack() {
    let start = strollPosition(elapsed: 0, duration: 6, laneWidth: 400, spriteWidth: 30)
    let mid = strollPosition(elapsed: 3, duration: 6, laneWidth: 400, spriteWidth: 30)
    let quarter = strollPosition(elapsed: 1.5, duration: 6, laneWidth: 400, spriteWidth: 30)
    let end = strollPosition(elapsed: 6, duration: 6, laneWidth: 400, spriteWidth: 30)
    #expect(start.x == 0)
    #expect(abs(quarter.x - 185) < 0.001)
    #expect(abs(mid.x - 370) < 0.001)
    #expect(abs(end.x) < 0.001)
}

@Test func strollClampsToLane() {
    let before = strollPosition(elapsed: -5, duration: 6, laneWidth: 400, spriteWidth: 30)
    let after = strollPosition(elapsed: 99, duration: 6, laneWidth: 400, spriteWidth: 30)
    #expect(before.x == 0)
    #expect(after.x == 0)
    let narrow = strollPosition(elapsed: 3, duration: 6, laneWidth: 20, spriteWidth: 30)
    #expect(narrow.x == 0)
    let zeroDuration = strollPosition(elapsed: 1, duration: 0, laneWidth: 400, spriteWidth: 30)
    #expect(zeroDuration.x == 0)
}

@Test func strollFacesLeftOnReturn() {
    #expect(!strollPosition(elapsed: 1, duration: 6, laneWidth: 400, spriteWidth: 30).facingLeft)
    #expect(strollPosition(elapsed: 4, duration: 6, laneWidth: 400, spriteWidth: 30).facingLeft)
}

@Test func chatterPrefersWorkingThenNeedsInputThenFinished() {
    let all = [rec("i", .idle), rec("f", .finished), rec("n", .needsInput), rec("w", .working)]
    #expect(chatterTarget(sessions: all, now: base, pick: { $0.first })?.sessionID == "w")
    #expect(chatterTarget(sessions: Array(all.dropLast()), now: base, pick: { $0.first })?.sessionID == "n")
    #expect(chatterTarget(sessions: Array(all.prefix(2)), now: base, pick: { $0.first })?.sessionID == "f")
    #expect(chatterTarget(sessions: [rec("i", .idle)], now: base, pick: { $0.first }) == nil)
}

@Test func avatarTapStaysOnFocusWhileRepliesShow() {
    let all = [rec("n", .needsInput), rec("w", .working)]
    let withReplies = avatarTapTarget(sessions: all, focusID: "n", repliesShowing: true, now: base, pick: { $0.first })
    #expect(withReplies?.sessionID == "n")
    let without = avatarTapTarget(sessions: all, focusID: "n", repliesShowing: false, now: base, pick: { $0.first })
    #expect(without?.sessionID == "w")
    let noneActive = avatarTapTarget(sessions: [rec("i", .idle)], focusID: "i", repliesShowing: false, now: base, pick: { $0.first })
    #expect(noneActive?.sessionID == "i")
}
