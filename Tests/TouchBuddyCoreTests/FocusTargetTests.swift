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
        #expect(script.contains("with timeout of 5 seconds"))
        #expect(script.contains("end timeout"))
        #expect(script.contains("set miniaturized of w to false"))
        #expect(script.range(of: "set miniaturized of w to false")!.lowerBound < script.range(of: "select w")!.lowerBound)
        #expect(script.hasSuffix("return \"missing:\" & lastErr"))
    }

    @Test func selectScriptDereferencesCollectionsAndTriesEachWindow() {
        let script = itermSelectScript(uniqueID: uuid)
        #expect(script.contains("repeat with w in (get windows)"))
        #expect(script.contains("repeat with t in (get tabs of w)"))
        #expect(script.contains("repeat with s in (get sessions of t)"))
        let lines = script.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let loop = lines.firstIndex(of: "repeat with w in (get windows)")!
        let tryLine = lines.firstIndex(of: "try")!
        let endTry = lines.firstIndex(of: "end try")!
        let reveal = lines.firstIndex(of: "if isHotkey then reveal hotkey window w")!
        #expect(loop < tryLine && tryLine < endTry)
        #expect(endTry < lines.firstIndex(of: "set w to foundW")!)
        #expect(lines.firstIndex(of: "select s")! > endTry && reveal > endTry)
        #expect(lines.contains("on error errMsg number errNum"))
        #expect(lines.contains("if errNum is -1712 or errNum is -128 then error errMsg number errNum"))
        #expect(lines.contains("return \"missing:\" & lastErr"))
    }

    @Test func selectScriptRevealsHotkeyWindowBeforeSelecting() {
        let script = itermSelectScript(uniqueID: uuid)
        #expect(script.contains("is hotkey window of w"))
        let reveal = script.range(of: "reveal hotkey window w")!.lowerBound
        #expect(reveal < script.range(of: "select w")!.lowerBound)
        #expect(reveal < script.range(of: "select s")!.lowerBound)
        #expect(script.contains("if not isHotkey then activate"))
    }

    @Test func hotkeyFallbackNeverActivatesOrCreates() {
        let script = itermRevealHotkeyScript
        #expect(script.contains("reveal hotkey window w"))
        #expect(script.contains("with timeout of 5 seconds"))
        for forbidden in ["activate", "create window", "create tab", "write text", "do shell script"] {
            #expect(!script.contains(forbidden))
        }
        #expect(script.hasSuffix("return \"none\""))
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
