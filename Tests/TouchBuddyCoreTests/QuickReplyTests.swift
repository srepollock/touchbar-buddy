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
    updatedAt: Date = t0,
    tool: String? = "Bash",
    toolUseID: String? = "toolu_1",
    inFlight: [String]? = ["toolu_1"]
) -> SessionRecord {
    SessionRecord(
        sessionID: "a", cwd: "/tmp/a", projectName: "a", state: state, speechKind: kind,
        toolName: tool, updatedAt: updatedAt, startedAt: Date(timeIntervalSince1970: 0), itermSessionID: iterm,
        pendingQuestion: options == nil ? nil : "Q?", pendingOptions: options, pendingToolUseID: toolUseID,
        inFlightToolUseIDs: inFlight
    )
}

@Suite struct QuickReplyTests {
    @Test func permissionGivesAllowAlwaysDeny() {
        #expect(quickReplies(for: record()) == [.allow, .allowAlways, .deny])
    }

    @Test func editGivesAllowDenyOnly() {
        #expect(quickReplies(for: record(tool: "Edit")) == [.allow, .deny])
    }

    @Test func builtInToolsGetAllowDenyWithoutAlways() {
        for tool in ["Edit", "MultiEdit", "Write", "NotebookEdit", "Read", "Glob", "Grep", "WebFetch", "WebSearch"] {
            #expect(quickReplies(for: record(tool: tool)) == [.allow, .deny], "\(tool)")
        }
    }

    @Test func alwaysIsBashOnly() {
        #expect(quickReplies(for: record(tool: "Bash")).contains(.allowAlways))
        for tool in ["Edit", "Read", "Write", "WebFetch"] {
            #expect(!quickReplies(for: record(tool: tool)).contains(.allowAlways))
        }
    }

    @Test func excludedToolsGetNoPermissionReplies() {
        for tool in ["ExitPlanMode", "AskUserQuestion", "Task", "Agent", "mcp__x__y", "mcp__x__Read", nil] {
            #expect(quickReplies(for: record(tool: tool)).isEmpty)
        }
    }

    @Test func noRepliesWithoutToolUseID() {
        #expect(quickReplies(for: record(toolUseID: nil)).isEmpty)
        #expect(quickReplies(for: record(kind: .question, options: ["A", "B"], toolUseID: nil)).isEmpty)
    }

    @Test func choicesCappedAtNine() {
        let options = (1...12).map { "o\($0)" }
        #expect(quickReplies(for: record(kind: .question, options: options, tool: "AskUserQuestion")).count == 9)
    }

    @Test func staleWhenToolUseIDChangedInSameSecond() {
        #expect(!isReplyStillValid(shownFor: record(), current: record(toolUseID: "toolu_2")))
    }

    @Test func staleWhenAnyFieldChanged() {
        #expect(!isReplyStillValid(shownFor: record(), current: record(tool: "Edit")))
    }

    @Test func footersAreKnownMarkers() {
        #expect(promptFooters(for: .allow) == [permissionPromptFooter])
        #expect(promptFooters(for: .deny) == [permissionPromptFooter])
        #expect(promptFooters(for: .choose(index: 1, label: "x")) == [questionPromptFooter])
        #expect(permissionPromptFooter == "Esc to cancel · Tab to amend")
        #expect(questionPromptFooter == "Enter to select ·")
        #expect(knownPromptFooters == [permissionPromptFooter, questionPromptFooter])
    }

    @Test func writeScriptChecksScreenBeforeTyping() {
        let script = itermWriteScript(uniqueID: uuid, keystrokes: "1", footers: [permissionPromptFooter])
        #expect(script.contains("trimmedLine ends with \"Esc to cancel · Tab to amend\""))
        #expect(!script.contains("Enter to select"))
        #expect(!script.contains("contains \"Tab"))
        #expect(script.contains("seen is greater than or equal to 3"))
        #expect(script.contains("return \"noprompt\""))
        let contains = script.range(of: "trimmedLine ends with")!.lowerBound
        let write = script.range(of: "write text")!.lowerBound
        #expect(contains < write)
    }

    @Test func questionScriptUsesStartsWith() {
        let script = itermWriteScript(uniqueID: uuid, keystrokes: "2", footers: [questionPromptFooter])
        #expect(script.contains("trimmedLine starts with \"Enter to select ·\""))
        #expect(!script.contains("ends with"))
    }

    @Test func repliesOnlyWhenExactlyOneToolInFlight() {
        #expect(quickReplies(for: record(inFlight: ["toolu_1", "toolu_2"])).isEmpty)
        #expect(quickReplies(for: record(inFlight: nil)).isEmpty)
        #expect(quickReplies(for: record(inFlight: [])).isEmpty)
        #expect(quickReplies(for: record(inFlight: ["toolu_1"])) == [.allow, .allowAlways, .deny])
        #expect(quickReplies(for: record(kind: .question, options: ["A", "B"], tool: "AskUserQuestion", inFlight: ["a", "b"])).isEmpty)
    }

    @Test func writeScriptRejectsUnknownFooters() {
        let script = itermWriteScript(uniqueID: uuid, keystrokes: "1", footers: ["x\" or true or \""])
        #expect(!script.contains("write text"))
    }

    @Test func tapsIgnoredWhileSettling() {
        let built = Date(timeIntervalSince1970: 100)
        #expect(!isReplyTapAccepted(builtAt: built, now: built.addingTimeInterval(0.2)))
        #expect(isReplyTapAccepted(builtAt: built, now: built.addingTimeInterval(0.5)))
    }

    @Test func fullwidthDigitsAndNonAsciiUUIDRejected() {
        #expect(!itermWriteScript(uniqueID: uuid, keystrokes: "\u{FF11}").contains("write text"))
        #expect(!isValidITermUUID(String(repeating: "\u{FF10}", count: 36)))
        #expect(isValidITermUUID(uuid))
    }

    @Test func questionGivesNumberedChoices() {
        let r = record(kind: .question, options: ["Postgres", "SQLite", "Neither"], tool: "AskUserQuestion")
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

    @Test func validWhenOnlyUpdatedAtChanged() {
        let shown = record()
        #expect(isReplyStillValid(shownFor: shown, current: record(updatedAt: t0.addingTimeInterval(1))))
    }

    @Test func staleWhenPromptIdentityChanged() {
        let shown = record()
        #expect(!isReplyStillValid(shownFor: shown, current: record(inFlight: ["toolu_1", "toolu_2"])))
        #expect(!isReplyStillValid(shownFor: shown, current: record(kind: .question)))
        #expect(!isReplyStillValid(shownFor: shown, current: record(iterm: nil)))
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
        #expect(script.contains("with timeout of 5 seconds"))
        #expect(script.contains("end timeout"))
        #expect(script.hasSuffix("return \"missing:\" & lastErr"))
    }

    @Test func writeScriptUsesDereferencedTryWrappedLookup() {
        let script = itermWriteScript(uniqueID: uuid, keystrokes: "1")
        #expect(script.contains("repeat with w in (get windows)"))
        #expect(script.contains("repeat with t in (get tabs of w)"))
        #expect(script.contains("repeat with s in (get sessions of t)"))
        #expect(script.contains("end try"))
        #expect(!script.contains("activate"))
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
