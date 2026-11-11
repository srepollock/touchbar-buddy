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

    // MCP tools may send any shape; a mistyped field must not drop the event.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        command = try? container.decodeIfPresent(String.self, forKey: .command)
        filePath = try? container.decodeIfPresent(String.self, forKey: .filePath)
        description = try? container.decodeIfPresent(String.self, forKey: .description)
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

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try container.decode(String.self, forKey: .sessionID)
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
        hookEventName = try container.decode(String.self, forKey: .hookEventName)
        toolName = try container.decodeIfPresent(String.self, forKey: .toolName)
        toolInput = try? container.decodeIfPresent(ToolInputSummary.self, forKey: .toolInput)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        notificationType = try container.decodeIfPresent(String.self, forKey: .notificationType)
    }

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
