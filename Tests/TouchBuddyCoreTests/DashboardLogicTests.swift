import Foundation
import Testing
@testable import TouchBuddyCore

private func record(_ id: String = "a", state: SessionState = .needsInput, at: TimeInterval = 100) -> SessionRecord {
    SessionRecord(
        sessionID: id, cwd: "/tmp/\(id)", projectName: id, state: state, speechKind: .permission,
        updatedAt: Date(timeIntervalSince1970: at), startedAt: Date(timeIntervalSince1970: 0)
    )
}

private let t = Date(timeIntervalSince1970: 200)

@Suite struct DashboardLogicTests {
    @Test func repicksWhenNoLineYet() {
        let key = speechKey(for: record(), now: t)
        #expect(shouldRepickSpeech(previous: key, current: key, hasLine: false))
    }

    @Test func keepsLineWhenStateAndUpdatedAtUnchanged() {
        let key = speechKey(for: record(), now: t)
        #expect(!shouldRepickSpeech(previous: key, current: speechKey(for: record(), now: t), hasLine: true))
    }

    @Test func keepsLineWhenNeedsInputRewrittenWithSamePrompt() {
        let base = speechKey(for: record(), now: t)
        #expect(!shouldRepickSpeech(previous: base, current: speechKey(for: record(at: 101), now: t), hasLine: true))
    }

    @Test func repicksWhenNeedsInputPromptChanges() {
        let base = speechKey(for: record(), now: t)
        var other = record()
        other.detail = "rm -rf build"
        #expect(shouldRepickSpeech(previous: base, current: speechKey(for: other, now: t), hasLine: true))
    }

    @Test func keepsLineWhenOnlyParallelCallsChange() {
        var waiting = record()
        waiting.inFlightToolUseIDs = ["A"]
        var busier = waiting
        busier.inFlightToolUseIDs = ["A", "B"]
        #expect(!shouldRepickSpeech(previous: speechKey(for: waiting, now: t), current: speechKey(for: busier, now: t), hasLine: true))
    }

    @Test func repicksWhenFinishedDecaysToIdle() {
        let finished = record(state: .finished, at: 100)
        let fresh = speechKey(for: finished, now: Date(timeIntervalSince1970: 200))
        let decayed = speechKey(for: finished, now: Date(timeIntervalSince1970: 100 + finishedDecaySeconds + 1))
        #expect(shouldRepickSpeech(previous: fresh, current: decayed, hasLine: true))
    }

    @Test func repicksOnNewUpdatedAtStateOrSession() {
        let base = speechKey(for: record(state: .working), now: t)
        #expect(shouldRepickSpeech(previous: base, current: speechKey(for: record(state: .working, at: 101), now: t), hasLine: true))
        #expect(shouldRepickSpeech(previous: base, current: speechKey(for: record(), now: t), hasLine: true))
        #expect(shouldRepickSpeech(previous: base, current: speechKey(for: record("b", state: .working), now: t), hasLine: true))
        #expect(shouldRepickSpeech(previous: base, current: nil, hasLine: true))
    }

    @Test func stripsEmojiAndTidiesWhitespace() {
        #expect(stripEmoji("Done \u{1F389} with build") == "Done with build")
        #expect(stripEmoji("\u{1F44D}\u{1F3FD} ok \u{2705}") == "ok")
        #expect(stripEmoji("v2 build #3 *done*") == "v2 build #3 *done*")
        #expect(stripEmoji("\u{1F468}\u{200D}\u{1F4BB} coding") == "coding")
        #expect(stripEmoji("heart \u{2764}\u{FE0F}") == "heart")
    }

    @Test func marqueePausesThenScrollsThenLoops() {
        #expect(marqueeOffset(elapsed: 0.5, cycleLength: 300) == 0)
        #expect(marqueeOffset(elapsed: 2, cycleLength: 300) == 30)
        // period = 1 + 10 = 11s
        #expect(marqueeOffset(elapsed: 11.5, cycleLength: 300) == 0)
        #expect(marqueeOffset(elapsed: 13, cycleLength: 300) == 30)
        #expect(marqueeOffset(elapsed: 5, cycleLength: 0) == 0)
    }

    @Test func marqueeHoldsAtEndBeforeLooping() {
        // period = 1 + 10 + 1 = 12s
        #expect(marqueeOffset(elapsed: 11.5, cycleLength: 300, endPause: 1) == 300)
        #expect(marqueeOffset(elapsed: 12.5, cycleLength: 300, endPause: 1) == 0)
    }

    @Test func marqueeElapsedResumesFromOffset() {
        let elapsed = marqueeElapsed(forOffset: 90)
        #expect(marqueeOffset(elapsed: elapsed, cycleLength: 300) == 90)
        #expect(marqueeElapsed(forOffset: -5) == 1)
    }
}
