import Foundation

public struct ToolInputSummary: Decodable, Sendable {
    public let command: String?
    public let filePath: String?
    public let description: String?

    public init(command: String?, filePath: String?, description: String?) {
        self.command = command
        self.filePath = filePath
        self.description = description
    }

    enum CodingKeys: String, CodingKey {
        case command
        case filePath = "file_path"
        case description
    }
}

public struct HookPayload: Decodable, Sendable {
    public let sessionID: String
    public let cwd: String?
    public let hookEventName: String
    public let toolName: String?
    public let toolInput: ToolInputSummary?
    public let message: String?
    public let notificationType: String?

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case cwd
        case hookEventName = "hook_event_name"
        case toolName = "tool_name"
        case toolInput = "tool_input"
        case message
        case notificationType = "notification_type"
    }
}

public struct HookContext: Sendable {
    public let claudePID: Int32?
    public let itermSessionID: String?
    public let entrypoint: String?
    public let now: Date

    public init(claudePID: Int32?, itermSessionID: String?, entrypoint: String?, now: Date) {
        self.claudePID = claudePID
        self.itermSessionID = itermSessionID
        self.entrypoint = entrypoint
        self.now = now
    }
}
