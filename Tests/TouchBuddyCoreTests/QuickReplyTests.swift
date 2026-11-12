import Foundation
import Testing
@testable import TouchBuddyCore

private let uuid = "749C8A37-14BF-4A32-BBE8-805358724574"
private let t0 = Date(timeIntervalSince1970: 1_000)

private func record(
    state: SessionState = .needsInput,
    kind: SpeechKind = .permission,
    options: [String]? = nil,
    iterm: String? = "w0t1p0:\(uuid)",
    updatedAt: Date = t0
) -> SessionRecord {
    SessionRecord(
        sessionID: "a", cwd: "/tmp/a", projectName: "a", state: state, speechKind: kind,
        updatedAt: updatedAt, startedAt: Date(timeIntervalSince1970: 0),
        itermSessionID: iterm, pendingQuestion: options == nil ? nil : "Q?", pendingOptions: options
    )
}

@Suite struct QuickReplyTests {
    @Test func permissionGivesAllowAlwaysDeny() {
        #expect(quickReplies(for: record()) == [.allow, .allowAlways, .deny])
    }

    @Test func questionGivesNumberedChoices() {
        let r = record(kind: .question, options: ["Postgres", "SQLite", "Neither"])
        #expect(quickReplies(for: r) == [
            .choose(index: 1, label: "Postgres"), .choose(index: 2, label: "SQLite"), .choose(index: 3, label: "Neither"),
        ])
    }

    @Test func questionWithoutOptionsGivesNothing() {
        #expect(quickReplies(for: record(kind: .question)).isEmpty)
        #expect(quickReplies(for: record(kind: .question, options: [])).isEmpty)
    }

    @Test func noRepliesWhenNotNeedsInput() {
        #expect(quickReplies(for: record(state: .working, kind: .working)).isEmpty)
        #expect(quickReplies(for: record(state: .finished, kind: .finished)).isEmpty)
    }

    @Test func noRepliesWithoutValidItermID() {
        #expect(quickReplies(for: record(iterm: nil)).isEmpty)
        #expect(quickReplies(for: record(iterm: "w0t0p0:\" & do shell script \"x")).isEmpty)
    }

    @Test func keystrokeWhitelist() {
        #expect(keystrokes(for: .allow) == "1")
        #expect(keystrokes(for: .allowAlways) == "2")
        #expect(keystrokes(for: .deny) == "\u{1B}")
        #expect(keystrokes(for: .choose(index: 3, label: "x")) == "3")
        #expect(keystrokes(for: .choose(index: 12, label: "x")) == "")
        #expect(keystrokes(for: .choose(index: 0, label: "x")) == "")
    }

    @Test func staleWhenUpdatedAtChanged() {
        let shown = record()
        #expect(!isReplyStillValid(shownFor: shown, current: record(updatedAt: t0.addingTimeInterval(1))))
    }

    @Test func staleWhenStateChanged() {
        #expect(!isReplyStillValid(shownFor: record(), current: record(state: .working, kind: .working)))
    }

    @Test func staleWhenSessionGone() {
        #expect(!isReplyStillValid(shownFor: record(), current: nil))
    }

    @Test func validWhenUnchanged() {
        #expect(isReplyStillValid(shownFor: record(), current: record()))
    }

    @Test func writeScriptEmbedsOnlyUUIDAndKeys() {
        let script = itermWriteScript(uniqueID: uuid, keystrokes: "1")
        #expect(!script.contains("do shell script"))
        #expect(script.contains("newline NO"))
        #expect(script.contains("\"\(uuid)\""))
        #expect(script.contains("write text \"1\""))
        #expect(script.components(separatedBy: uuid).count == 2)
    }

    @Test func writeScriptEmitsEscAsCharacterID() {
        let script = itermWriteScript(uniqueID: uuid, keystrokes: "\u{1B}")
        #expect(script.contains("write text (character id 27) newline NO"))
        #expect(!script.unicodeScalars.contains { $0.value == 0x1B })
    }

    @Test func writeScriptGuardsRunningAndTimeout() {
        let script = itermWriteScript(uniqueID: uuid, keystrokes: "1")
        #expect(script.contains("if application \"iTerm2\" is running then"))
        #expect(script.contains("with timeout of 3 seconds"))
        #expect(script.contains("end timeout"))
        #expect(script.hasSuffix("return \"missing\""))
    }

    @Test func writeScriptRejectsBadInputs() {
        let evilID = itermWriteScript(uniqueID: "x\" & do shell script \"y", keystrokes: "1")
        #expect(!evilID.contains("do shell script"))
        #expect(!evilID.contains("write text"))
        let evilKeys = itermWriteScript(uniqueID: uuid, keystrokes: "1\" & (do shell script \"y\") & \"")
        #expect(!evilKeys.contains("write text"))
        #expect(!itermWriteScript(uniqueID: uuid, keystrokes: "").contains("write text"))
        #expect(!itermWriteScript(uniqueID: uuid, keystrokes: "12").contains("write text"))
    }

    @Test func yesNoPairDetection() {
        #expect(isYesNo(["Yes", "No"]))
        #expect(isYesNo(["no", "YES"]))
        #expect(isYesNo(["Yes, proceed", "No, cancel"]))
        #expect(isYesNo(["Yes - do it", "No (keep as is)"]))
        #expect(!isYesNo(["Yes", "Maybe"]))
        #expect(!isYesNo(["Yes", "Yes please"]))
        #expect(!isYesNo(["Yesterday", "Nobody"]))
        #expect(!isYesNo(["Yes", "No", "Skip"]))
        #expect(!isYesNo(["Yes"]))
        #expect(!isYesNo([]))
    }

    @Test func polarityOfLabels() {
        #expect(yesNoPolarity("Yes, go") == true)
        #expect(yesNoPolarity("no") == false)
        #expect(yesNoPolarity("Maybe") == nil)
    }
}
