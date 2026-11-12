import Foundation
import Testing
@testable import TouchBuddyCore

private let now = Date(timeIntervalSince1970: 1_000_000)

private func payload(_ json: String) throws -> HookPayload {
    try JSONDecoder().decode(HookPayload.self, from: Data(json.utf8))
}

private func event(
    _ name: String,
    cwd: String? = "/Users/x/projects/touchbar-app",
    extra: String = ""
) throws -> HookPayload {
    let cwdField = cwd.map { "\"cwd\": \"\($0)\"," } ?? ""
    return try payload(
        "{\"session_id\": \"s1\", \(cwdField) \"hook_event_name\": \"\(name)\"\(extra.isEmpty ? "" : ", " + extra)}"
    )
}

private let context = HookContext(claudePID: 42, itermSessionID: "iterm-1", entrypoint: "cli", now: now)
private let emptyContext = HookContext(claudePID: nil, itermSessionID: nil, entrypoint: nil, now: now)

private func upserted(_ update: SessionUpdate) throws -> SessionRecord {
    guard case .upsert(let record) = update else {
        throw TestFailure.notUpsert(update)
    }
    return record
}

private enum TestFailure: Error { case notUpsert(SessionUpdate) }

private func existingRecord() -> SessionRecord {
    SessionRecord(
        sessionID: "s1", cwd: "/Users/x/projects/touchbar-app", projectName: "touchbar-app",
        state: .idle, speechKind: .idle, detail: nil, toolName: nil,
        updatedAt: Date(timeIntervalSince1970: 500), startedAt: Date(timeIntervalSince1970: 100),
        claudePID: 7, itermSessionID: "iterm-old", entrypoint: "cli"
    )
}

@Test func sessionStartCreatesIdle() throws {
    let record = try upserted(reduce(existing: nil, payload: event("SessionStart"), context: context))
    #expect(record.state == .idle)
    #expect(record.speechKind == .idle)
    #expect(record.projectName == "touchbar-app")
    #expect(record.claudePID == 42)
    #expect(record.itermSessionID == "iterm-1")
    #expect(record.entrypoint == "cli")
}

@Test func userPromptSubmitIsWorking() throws {
    let record = try upserted(reduce(existing: existingRecord(), payload: event("UserPromptSubmit"), context: context))
    #expect(record.state == .working)
    #expect(record.speechKind == .working)
}

@Test func preToolUseBashIsWorkingWithSummary() throws {
    let p = try event("PreToolUse", extra: "\"tool_name\": \"Bash\", \"tool_input\": {\"command\": \"bun test\"}")
    let record = try upserted(reduce(existing: existingRecord(), payload: p, context: context))
    #expect(record.state == .working)
    #expect(record.toolName == "Bash")
    #expect(record.detail == "bun test")
}

@Test func preToolUseAskUserQuestionNeedsInput() throws {
    let p = try event("PreToolUse", extra: "\"tool_name\": \"AskUserQuestion\", \"tool_input\": {}")
    let record = try upserted(reduce(existing: existingRecord(), payload: p, context: context))
    #expect(record.state == .needsInput)
    #expect(record.speechKind == .question)
}

@Test func postToolUseIsWorking() throws {
    let p = try event("PostToolUse", extra: "\"tool_name\": \"Bash\"")
    let record = try upserted(reduce(existing: existingRecord(), payload: p, context: context))
    #expect(record.state == .working)
}

@Test func notificationPermissionNeedsInput() throws {
    let p = try event(
        "Notification",
        extra: "\"notification_type\": \"permission_prompt\", \"message\": \"Claude needs your permission to use Bash\""
    )
    let record = try upserted(reduce(existing: existingRecord(), payload: p, context: context))
    #expect(record.state == .needsInput)
    #expect(record.speechKind == .permission)
    #expect(record.detail == "Claude needs your permission to use Bash")
}

@Test func notificationElicitationNeedsInput() throws {
    let p = try event("Notification", extra: "\"notification_type\": \"elicitation_dialog\"")
    let record = try upserted(reduce(existing: existingRecord(), payload: p, context: context))
    #expect(record.state == .needsInput)
}

@Test func notificationIdlePromptUnchanged() throws {
    let p = try event("Notification", extra: "\"notification_type\": \"idle_prompt\"")
    #expect(reduce(existing: existingRecord(), payload: p, context: context) == .unchanged)
}

@Test func notificationWithoutTypeFallsBackToMessage() throws {
    let permission = try event("Notification", extra: "\"message\": \"Claude needs your permission to use Bash\"")
    let record = try upserted(reduce(existing: existingRecord(), payload: permission, context: context))
    #expect(record.state == .needsInput)

    let waiting = try event("Notification", extra: "\"message\": \"Claude is waiting for your input\"")
    #expect(reduce(existing: existingRecord(), payload: waiting, context: context) == .unchanged)
}

@Test func stopIsFinished() throws {
    let record = try upserted(reduce(existing: existingRecord(), payload: event("Stop"), context: context))
    #expect(record.state == .finished)
    #expect(record.speechKind == .finished)
}

@Test func sessionEndDeletes() throws {
    let update = reduce(existing: existingRecord(), payload: try event("SessionEnd"), context: context)
    #expect(update == .delete(sessionID: "s1"))
}

@Test func unknownEventUnchanged() throws {
    #expect(reduce(existing: existingRecord(), payload: try event("SubagentStop"), context: context) == .unchanged)
}

@Test func eventWithoutExistingCreatesRecord() throws {
    let p = try event("PreToolUse", extra: "\"tool_name\": \"Bash\", \"tool_input\": {\"command\": \"ls\"}")
    let record = try upserted(reduce(existing: nil, payload: p, context: context))
    #expect(record.startedAt == now)
    #expect(record.updatedAt == now)
}

@Test func existingFieldsPreserved() throws {
    let existing = existingRecord()
    let record = try upserted(reduce(existing: existing, payload: event("Stop", cwd: nil), context: emptyContext))
    #expect(record.startedAt == existing.startedAt)
    #expect(record.itermSessionID == "iterm-old")
    #expect(record.claudePID == 7)
    #expect(record.cwd == existing.cwd)
    #expect(record.updatedAt == now)
}

@Test func missingCwdUsesUnknownProject() throws {
    let record = try upserted(reduce(existing: nil, payload: event("SessionStart", cwd: nil), context: emptyContext))
    #expect(record.projectName == "unknown")
}

@Test func decodingIgnoresUnknownFields() throws {
    let p = try payload("""
    {"session_id": "s1", "hook_event_name": "Stop", "transcript_path": "/tmp/t", "permission_mode": "default"}
    """)
    #expect(p.cwd == nil)
    #expect(p.toolName == nil)
}

@Test func toolSummaryTruncates() {
    let long = String(repeating: "a", count: 120)
    let bash = toolSummary(toolName: "Bash", input: ToolInputSummary(command: long, filePath: nil, description: nil))
    #expect(bash?.count == 40)
    #expect(bash?.hasSuffix("…") == true)

    let edit = toolSummary(toolName: "Edit", input: ToolInputSummary(command: nil, filePath: "/a/b/main.swift", description: nil))
    #expect(edit == "main.swift")

    #expect(toolSummary(toolName: "Mystery", input: nil) == "Mystery")
    #expect(toolSummary(toolName: nil, input: nil) == nil)
}

@Test func nonStringToolInputStillDecodes() throws {
    let weird = try event(
        "PreToolUse",
        extra: "\"tool_name\": \"mcp__x\", \"tool_input\": {\"description\": 42, \"command\": [\"a\"]}"
    )
    #expect(weird.toolInput?.command == nil)
    #expect(weird.toolInput?.description == nil)
    let weirdRecord = try upserted(reduce(existing: nil, payload: weird, context: context))
    #expect(weirdRecord.detail == "mcp__x")

    let scalar = try event("PreToolUse", extra: "\"tool_name\": \"mcp__x\", \"tool_input\": \"x\"")
    #expect(scalar.toolInput?.command == nil)
    #expect(scalar.toolInput?.filePath == nil)
    let scalarRecord = try upserted(reduce(existing: nil, payload: scalar, context: context))
    #expect(scalarRecord.state == .working)
}

@Test func missingCwdPreservesExistingProject() throws {
    for cwd in [nil, ""] as [String?] {
        let p = try event("UserPromptSubmit", cwd: cwd)
        let record = try upserted(reduce(existing: existingRecord(), payload: p, context: context))
        #expect(record.cwd == "/Users/x/projects/touchbar-app")
        #expect(record.projectName == "touchbar-app")
    }
    let fresh = try upserted(reduce(existing: nil, payload: event("UserPromptSubmit", cwd: ""), context: context))
    #expect(fresh.projectName == "unknown")
    #expect(fresh.cwd == "")
}

private func askEvent(questions: String) throws -> HookPayload {
    try event(
        "PreToolUse",
        extra: "\"tool_name\": \"AskUserQuestion\", \"tool_input\": {\"questions\": \(questions)}"
    )
}

@Test func askUserQuestionRecordsOptions() throws {
    let p = try askEvent(questions: """
    [{"question": "Which db?", "header": "DB", "multiSelect": false,
      "options": [{"label": "Postgres", "description": "x"}, {"label": "SQLite", "description": "y"}]}]
    """)
    let record = try upserted(reduce(existing: existingRecord(), payload: p, context: context))
    #expect(record.state == .needsInput)
    #expect(record.pendingQuestion == "Which db?")
    #expect(record.pendingOptions == ["Postgres", "SQLite"])
}

@Test func multiSelectQuestionRecordsNoOptions() throws {
    let p = try askEvent(questions: """
    [{"question": "Which?", "multiSelect": true, "options": [{"label": "A"}, {"label": "B"}]}]
    """)
    let record = try upserted(reduce(existing: existingRecord(), payload: p, context: context))
    #expect(record.state == .needsInput)
    #expect(record.pendingOptions == nil)
}

@Test func multipleQuestionsRecordNoOptions() throws {
    let p = try askEvent(questions: """
    [{"question": "One?", "options": [{"label": "A"}, {"label": "B"}]},
     {"question": "Two?", "options": [{"label": "C"}, {"label": "D"}]}]
    """)
    let record = try upserted(reduce(existing: existingRecord(), payload: p, context: context))
    #expect(record.pendingQuestion == nil)
    #expect(record.pendingOptions == nil)
}

@Test func leavingNeedsInputClearsOptions() throws {
    let ask = try askEvent(questions: """
    [{"question": "Which?", "options": [{"label": "A"}, {"label": "B"}]}]
    """)
    let asked = try upserted(reduce(existing: existingRecord(), payload: ask, context: context))
    #expect(asked.pendingOptions == ["A", "B"])
    let after = try upserted(reduce(existing: asked, payload: event("PostToolUse", extra: "\"tool_name\": \"AskUserQuestion\""), context: context))
    #expect(after.state == .working)
    #expect(after.pendingQuestion == nil)
    #expect(after.pendingOptions == nil)
}

@Test func permissionNotificationLeavesOptionsNil() throws {
    let p = try event("Notification", extra: "\"notification_type\": \"permission_prompt\", \"message\": \"Claude needs your permission to use Bash\"")
    let record = try upserted(reduce(existing: existingRecord(), payload: p, context: context))
    #expect(record.state == .needsInput)
    #expect(record.pendingQuestion == nil)
    #expect(record.pendingOptions == nil)
}

@Test func mistypedQuestionsStillDecodeEvent() throws {
    let p = try askEvent(questions: "\"not an array\"")
    let record = try upserted(reduce(existing: existingRecord(), payload: p, context: context))
    #expect(record.state == .needsInput)
    #expect(record.pendingOptions == nil)
}

@Test func oldSessionFileWithoutNewFieldsDecodes() throws {
    let json = """
    {"sessionID": "s1", "cwd": "/x", "projectName": "x", "state": "idle", "speechKind": "idle",
     "updatedAt": "2026-11-11T00:00:00Z", "startedAt": "2026-11-11T00:00:00Z"}
    """
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let record = try decoder.decode(SessionRecord.self, from: Data(json.utf8))
    #expect(record.pendingQuestion == nil)
    #expect(record.pendingOptions == nil)
}

@Test func permissionNotificationAfterAskUserQuestionKeepsTheQuestion() throws {
    let ask = try askEvent(questions: """
    [{"question": "Which?", "options": [{"label": "A"}, {"label": "B"}]}]
    """)
    let asked = try upserted(reduce(existing: existingRecord(), payload: ask, context: context))
    let notification = try event(
        "Notification", extra: "\"notification_type\": \"permission_prompt\", \"message\": \"Claude needs your permission\""
    )
    #expect(reduce(existing: asked, payload: notification, context: context) == .unchanged)
}

@Test func permissionNotificationAfterBashStillNeedsInput() throws {
    var bash = existingRecord()
    bash.state = .working
    bash.toolName = "Bash"
    let notification = try event(
        "Notification", extra: "\"notification_type\": \"permission_prompt\", \"message\": \"Claude needs your permission\""
    )
    let record = try upserted(reduce(existing: bash, payload: notification, context: context))
    #expect(record.speechKind == .permission)
}

private func toolEvent(_ name: String, tool: String, id: String?, input: String = "{\"command\": \"touch a.txt\"}") throws -> HookPayload {
    let idField = id.map { ", \"tool_use_id\": \"\($0)\"" } ?? ""
    return try event(name, extra: "\"tool_name\": \"\(tool)\"\(idField), \"tool_input\": \(input)")
}

private let permissionNote = "\"notification_type\": \"permission_prompt\", \"message\": \"Claude needs your permission\""

@Test func preToolUseRecordsToolUseID() throws {
    let record = try upserted(reduce(existing: nil, payload: toolEvent("PreToolUse", tool: "Bash", id: "toolu_9"), context: context))
    #expect(record.pendingToolUseID == "toolu_9")
    #expect(record.state == .working)
}

@Test func permissionNotificationInheritsToolIdentity() throws {
    let pre = try upserted(reduce(existing: nil, payload: toolEvent("PreToolUse", tool: "Bash", id: "toolu_9"), context: context))
    let note = try upserted(reduce(existing: pre, payload: event("Notification", extra: permissionNote), context: context))
    #expect(note.state == .needsInput)
    #expect(note.speechKind == .permission)
    #expect(note.toolName == "Bash")
    #expect(note.detail == "touch a.txt")
    #expect(note.pendingToolUseID == "toolu_9")
}

@Test func leavingNeedsInputClearsToolUseID() throws {
    let pre = try upserted(reduce(existing: nil, payload: toolEvent("PreToolUse", tool: "Bash", id: "toolu_9"), context: context))
    let note = try upserted(reduce(existing: pre, payload: event("Notification", extra: permissionNote), context: context))
    let post = try upserted(reduce(existing: note, payload: toolEvent("PostToolUse", tool: "Bash", id: "toolu_9"), context: context))
    #expect(post.pendingToolUseID == nil)
}

@Test func notificationWithoutPreToolUseHasNoIdentity() throws {
    let note = try upserted(reduce(existing: existingRecord(), payload: event("Notification", extra: permissionNote), context: context))
    #expect(note.pendingToolUseID == nil)
    #expect(note.toolName == nil)
}

@Test func permissionNotificationAfterAskUserQuestionAnsweredIsNotSuppressed() throws {
    let ask = try askEvent(questions: "[{\"question\": \"Q?\", \"options\": [{\"label\": \"A\"}, {\"label\": \"B\"}]}]")
    let asked = try upserted(reduce(existing: nil, payload: ask, context: context))
    let post = try upserted(reduce(existing: asked, payload: event("PostToolUse", extra: "\"tool_name\": \"AskUserQuestion\""), context: context))
    let note = try upserted(reduce(existing: post, payload: event("Notification", extra: permissionNote), context: context))
    #expect(note.state == .needsInput)
    #expect(note.speechKind == .permission)
    #expect(note.pendingToolUseID == nil)
}

@Test func nonStringToolUseIDDoesNotDropEvent() throws {
    let p = try event("PreToolUse", extra: "\"tool_name\": \"Bash\", \"tool_use_id\": 5")
    let record = try upserted(reduce(existing: nil, payload: p, context: context))
    #expect(record.pendingToolUseID == nil)
}

private func permissionRequest(tool: String, command: String, id: String? = nil) throws -> HookPayload {
    try toolEvent("PermissionRequest", tool: tool, id: id, input: "{\"command\": \"\(command)\"}")
}

@Test func preToolUseTracksInFlightAndPostToolUseRemoves() throws {
    let a = try upserted(reduce(existing: nil, payload: toolEvent("PreToolUse", tool: "Bash", id: "A"), context: context))
    let b = try upserted(reduce(existing: a, payload: toolEvent("PreToolUse", tool: "Bash", id: "B"), context: context))
    #expect(b.inFlightToolUseIDs == ["A", "B"])
    let doneA = try upserted(reduce(existing: b, payload: toolEvent("PostToolUse", tool: "Bash", id: "A"), context: context))
    #expect(doneA.inFlightToolUseIDs == ["B"])
    let doneB = try upserted(reduce(existing: doneA, payload: toolEvent("PostToolUse", tool: "Bash", id: "B"), context: context))
    #expect(doneB.inFlightToolUseIDs == nil)
}

@Test func stopPromptSubmitAndSessionStartClearInFlight() throws {
    let a = try upserted(reduce(existing: nil, payload: toolEvent("PreToolUse", tool: "Bash", id: "A"), context: context))
    for name in ["Stop", "UserPromptSubmit", "SessionStart"] {
        let cleared = try upserted(reduce(existing: a, payload: event(name), context: context))
        #expect(cleared.inFlightToolUseIDs == nil)
    }
}

@Test func notificationKeepsInFlight() throws {
    let a = try upserted(reduce(existing: nil, payload: toolEvent("PreToolUse", tool: "Bash", id: "A"), context: context))
    let note = try upserted(reduce(existing: a, payload: event("Notification", extra: permissionNote), context: context))
    #expect(note.inFlightToolUseIDs == ["A"])
}

@Test func permissionRequestRefreshesDisplayWhenOneCallInFlight() throws {
    let a = try upserted(reduce(existing: nil, payload: toolEvent("PreToolUse", tool: "Bash", id: "A", input: "{\"command\": \"ls a\"}"), context: context))
    let request = try upserted(reduce(existing: a, payload: permissionRequest(tool: "Bash", command: "ls a --all"), context: context))
    #expect(request.state == .needsInput)
    #expect(request.speechKind == .permission)
    #expect(request.toolName == "Bash")
    #expect(request.detail == "ls a --all")
    #expect(request.pendingToolUseID == "A")
    #expect(quickReplies(for: withIterm(request)) == [.allow, .allowAlways, .deny])
}

@Test func overlappingPromptsGetNoRepliesAndNoDrift() throws {
    let a = try upserted(reduce(existing: nil, payload: toolEvent("PreToolUse", tool: "Bash", id: "A", input: "{\"command\": \"ls a\"}"), context: context))
    let b = try upserted(reduce(existing: a, payload: toolEvent("PreToolUse", tool: "Bash", id: "B", input: "{\"command\": \"ls b\"}"), context: context))
    let request = try upserted(reduce(existing: b, payload: permissionRequest(tool: "Edit", command: "other"), context: context))
    #expect(request.state == .needsInput)
    #expect(request.toolName == "Bash")
    #expect(request.detail == "ls b")
    #expect(request.inFlightToolUseIDs == ["A", "B"])
    #expect(quickReplies(for: withIterm(request)).isEmpty)
    let note = try upserted(reduce(existing: request, payload: event("Notification", extra: permissionNote), context: context))
    #expect(quickReplies(for: withIterm(note)).isEmpty)
}

@Test func notificationAfterPermissionRequestKeepsIdentity() throws {
    let a = try upserted(reduce(existing: nil, payload: toolEvent("PreToolUse", tool: "Bash", id: "A"), context: context))
    let request = try upserted(reduce(existing: a, payload: permissionRequest(tool: "Bash", command: "touch a.txt"), context: context))
    let note = try upserted(reduce(existing: request, payload: event("Notification", extra: permissionNote), context: context))
    #expect(note.toolName == "Bash")
    #expect(note.detail == "touch a.txt")
    #expect(note.pendingToolUseID == "A")
    #expect(note.inFlightToolUseIDs == ["A"])
}

@Test func permissionRequestForAskUserQuestionIsIgnored() throws {
    let ask = try askEvent(questions: "[{\"question\": \"Q?\", \"options\": [{\"label\": \"A\"}, {\"label\": \"B\"}]}]")
    let asked = try upserted(reduce(existing: nil, payload: ask, context: context))
    let p = try event("PermissionRequest", extra: "\"tool_name\": \"AskUserQuestion\", \"tool_input\": {}")
    #expect(reduce(existing: asked, payload: p, context: context) == .unchanged)
}

@Test func oldFileWithoutInFlightFieldsDecodes() throws {
    let json = """
    {"sessionID": "s1", "cwd": "/x", "projectName": "x", "state": "idle", "speechKind": "idle",
     "updatedAt": "2026-11-11T00:00:00Z", "startedAt": "2026-11-11T00:00:00Z", "pendingToolUseID": "t"}
    """
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let record = try decoder.decode(SessionRecord.self, from: Data(json.utf8))
    #expect(record.inFlightToolUseIDs == nil)
}

private func withIterm(_ record: SessionRecord) -> SessionRecord {
    var copy = record
    copy.itermSessionID = "w0t1p0:749C8A37-14BF-4A32-BBE8-805358724574"
    return copy
}
