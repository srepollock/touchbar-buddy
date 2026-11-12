import Foundation

public enum SessionUpdate: Equatable, Sendable {
    case upsert(SessionRecord)
    case delete(sessionID: String)
    case unchanged
}

private let summaryLimit = 40

public func toolSummary(toolName: String?, input: ToolInputSummary?) -> String? {
    if let command = input?.command, !command.isEmpty {
        return truncated(command)
    }
    if let filePath = input?.filePath, !filePath.isEmpty {
        return URL(fileURLWithPath: filePath).lastPathComponent
    }
    if let description = input?.description, !description.isEmpty {
        return truncated(description)
    }
    return toolName
}

private func truncated(_ text: String) -> String {
    guard text.count > summaryLimit else { return text }
    return String(text.prefix(summaryLimit - 1)) + "…"
}

private struct Transition {
    let state: SessionState
    let speechKind: SpeechKind
    let detail: String?
    let toolName: String?
    var pendingQuestion: String? = nil
    var pendingOptions: [String]? = nil
}

public func reduce(existing: SessionRecord?, payload: HookPayload, context: HookContext) -> SessionUpdate {
    if payload.hookEventName == "SessionEnd" {
        return .delete(sessionID: payload.sessionID)
    }
    guard let transition = transition(for: payload) else {
        return .unchanged
    }
    // Claude Code fires a generic permission_prompt notification right after PreToolUse AskUserQuestion;
    // letting it through would turn the question into an Allow/Deny prompt.
    if payload.hookEventName == "Notification", transition.speechKind == .permission,
       existing?.state == .needsInput, existing?.toolName == "AskUserQuestion" {
        return .unchanged
    }

    let payloadCwd = payload.cwd.flatMap { $0.isEmpty ? nil : $0 }
    let cwd = payloadCwd ?? existing?.cwd
    let projectName: String
    if payloadCwd == nil, let existing {
        projectName = existing.projectName
    } else {
        projectName = cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "unknown"
    }
    return .upsert(
        SessionRecord(
            sessionID: payload.sessionID,
            cwd: cwd ?? "",
            projectName: projectName,
            state: transition.state,
            speechKind: transition.speechKind,
            detail: transition.detail,
            toolName: transition.toolName,
            updatedAt: context.now,
            startedAt: existing?.startedAt ?? context.now,
            claudePID: context.claudePID ?? existing?.claudePID,
            itermSessionID: context.itermSessionID ?? existing?.itermSessionID,
            entrypoint: context.entrypoint ?? existing?.entrypoint,
            pendingQuestion: transition.state == .needsInput ? transition.pendingQuestion : nil,
            pendingOptions: transition.state == .needsInput ? transition.pendingOptions : nil
        )
    )
}

private func transition(for payload: HookPayload) -> Transition? {
    switch payload.hookEventName {
    case "SessionStart":
        return Transition(state: .idle, speechKind: .idle, detail: nil, toolName: nil)
    case "UserPromptSubmit":
        return Transition(state: .working, speechKind: .working, detail: nil, toolName: nil)
    case "PreToolUse":
        let summary = toolSummary(toolName: payload.toolName, input: payload.toolInput)
        if payload.toolName == "AskUserQuestion" {
            let single = singleSelectQuestion(payload.toolInput)
            return Transition(
                state: .needsInput, speechKind: .question, detail: summary, toolName: payload.toolName,
                pendingQuestion: single?.question, pendingOptions: single?.options
            )
        }
        return Transition(state: .working, speechKind: .working, detail: summary, toolName: payload.toolName)
    case "PostToolUse":
        return Transition(
            state: .working, speechKind: .working,
            detail: toolSummary(toolName: payload.toolName, input: payload.toolInput),
            toolName: payload.toolName
        )
    case "Notification":
        return notificationTransition(for: payload)
    case "Stop":
        return Transition(state: .finished, speechKind: .finished, detail: nil, toolName: nil)
    default:
        return nil
    }
}

private func notificationTransition(for payload: HookPayload) -> Transition? {
    let kind: SpeechKind
    switch payload.notificationType {
    case "permission_prompt":
        kind = .permission
    case "elicitation_dialog":
        kind = .question
    case nil:
        guard payload.message?.localizedCaseInsensitiveContains("permission") == true else { return nil }
        kind = .permission
    default:
        return nil
    }
    return Transition(state: .needsInput, speechKind: kind, detail: payload.message, toolName: nil)
}

private func singleSelectQuestion(_ input: ToolInputSummary?) -> (question: String?, options: [String])? {
    guard let questions = input?.questions, questions.count == 1, let only = questions.first,
          only.multiSelect != true, let options = only.options, !options.isEmpty
    else { return nil }
    return (only.question, options)
}
