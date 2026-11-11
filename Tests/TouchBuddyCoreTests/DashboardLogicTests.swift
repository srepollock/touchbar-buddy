import Foundation
import Testing
@testable import TouchBuddyCore

private func record(_ id: String = "a", state: SessionState = .needsInput, at: TimeInterval = 100) -> SessionRecord {
    SessionRecord(
        sessionID: id, cwd: "/tmp/\(id)", projectName: id, state: state, speechKind: .permission,
        updatedAt: Date(timeIntervalSince1970: at), startedAt: Date(timeIntervalSince1970: 0)
    )
}

@Suite struct DashboardLogicTests {
    @Test func repicksWhenNoLineYet() {
        let key = speechKey(for: record())
        #expect(shouldRepickSpeech(previous: key, current: key, hasLine: false))
    }

    @Test func keepsLineWhenStateAndUpdatedAtUnchanged() {
        let key = speechKey(for: record())
        #expect(!shouldRepickSpeech(previous: key, current: speechKey(for: record()), hasLine: true))
    }

    @Test func repicksOnNewUpdatedAtStateOrSession() {
        let base = speechKey(for: record())
        #expect(shouldRepickSpeech(previous: base, current: speechKey(for: record(at: 101)), hasLine: true))
        #expect(shouldRepickSpeech(previous: base, current: speechKey(for: record(state: .working)), hasLine: true))
        #expect(shouldRepickSpeech(previous: base, current: speechKey(for: record("b")), hasLine: true))
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
}
