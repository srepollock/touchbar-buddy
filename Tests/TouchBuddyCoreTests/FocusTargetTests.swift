import Foundation
import Testing
@testable import TouchBuddyCore

private let uuid = "749C8A37-14BF-4A32-BBE8-805358724574"

private func record(iterm: String? = nil, entrypoint: String? = nil) -> SessionRecord {
    SessionRecord(
        sessionID: "a", cwd: "/tmp/a", projectName: "a", state: .idle, speechKind: .finished,
        updatedAt: Date(timeIntervalSince1970: 100), startedAt: Date(timeIntervalSince1970: 0),
        itermSessionID: iterm, entrypoint: entrypoint
    )
}

@Suite struct FocusTargetTests {
    @Test func parsesValidItermID() {
        #expect(itermUniqueID(from: "w0t1p0:\(uuid)") == uuid)
        #expect(focusTarget(for: record(iterm: "w0t1p0:\(uuid)")) == .itermSession(uniqueID: uuid))
    }

    @Test func rejectsInjectionAttempt() {
        let evil = "w0t0p0:\" & do shell script \"x"
        #expect(itermUniqueID(from: evil) == nil)
        #expect(focusTarget(for: record(iterm: evil)) == .itermApp)
    }

    @Test func rejectsMalformedIDs() {
        #expect(itermUniqueID(from: "w0t1p0:") == nil)
        #expect(itermUniqueID(from: "nocolon") == nil)
        #expect(itermUniqueID(from: "w0t1p0:\(uuid)x") == nil)
        #expect(itermUniqueID(from: "xyz:\(uuid)") == nil)
        #expect(itermUniqueID(from: "w0t1p0:\(uuid)\n") == nil)
    }

    @Test func desktopEntrypointTargetsClaude() {
        #expect(focusTarget(for: record(entrypoint: "claude-desktop")) == .claudeDesktop)
        #expect(focusTarget(for: record(entrypoint: "Desktop")) == .claudeDesktop)
    }

    @Test func itermIDWinsOverDesktopEntrypoint() {
        #expect(focusTarget(for: record(iterm: "w0t1p0:\(uuid)", entrypoint: "desktop")) == .itermSession(uniqueID: uuid))
    }

    @Test func noIdsTargetsItermApp() {
        #expect(focusTarget(for: record()) == .itermApp)
        #expect(focusTarget(for: record(entrypoint: "cli")) == .itermApp)
    }

    @Test func scriptContainsOnlyTheUUID() {
        let script = itermSelectScript(uniqueID: uuid)
        #expect(script.contains("\"\(uuid)\""))
        #expect(script.contains("application \"iTerm2\""))
        let other = "00000000-0000-0000-0000-000000000000"
        #expect(itermSelectScript(uniqueID: other) == script.replacingOccurrences(of: uuid, with: other))
        #expect(script.components(separatedBy: uuid).count == 2)
    }

    @Test func selectScriptGuardsRunningTimeoutAndDeminiaturizes() {
        let script = itermSelectScript(uniqueID: uuid)
        #expect(script.contains("if application \"iTerm2\" is running then"))
        #expect(script.contains("with timeout of 3 seconds"))
        #expect(script.contains("end timeout"))
        #expect(script.contains("set miniaturized of w to false"))
        #expect(script.range(of: "set miniaturized of w to false")!.lowerBound < script.range(of: "select w")!.lowerBound)
        #expect(script.hasSuffix("return \"missing\""))
    }

    @Test func selectScriptRejectsInvalidUUID() {
        let script = itermSelectScript(uniqueID: "x\" & do shell script \"y")
        #expect(!script.contains("do shell script"))
        #expect(!script.contains("select w"))
    }

    @Test func nonAsciiDigitsRejected() {
        #expect(itermUniqueID(from: "w\u{0663}t1p0:\(uuid)") == nil)
    }
}
