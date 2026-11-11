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
