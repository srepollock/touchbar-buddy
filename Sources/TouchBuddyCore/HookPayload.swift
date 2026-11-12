import Foundation

public struct QuestionSummary: Decodable, Sendable, Equatable {
    public let question: String?
    public let multiSelect: Bool?
    public let options: [String]?

    public init(question: String?, multiSelect: Bool?, options: [String]?) {
        self.question = question
        self.multiSelect = multiSelect
        self.options = options
    }

    enum CodingKeys: String, CodingKey {
        case question
        case multiSelect
        case options
    }

    private struct Option: Decodable {
        let label: String?

        enum CodingKeys: String, CodingKey { case label }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            label = try? container.decodeIfPresent(String.self, forKey: .label)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        question = try? container.decodeIfPresent(String.self, forKey: .question)
        multiSelect = try? container.decodeIfPresent(Bool.self, forKey: .multiSelect)
        // Any unreadable option makes the whole list unusable: a partial list would renumber the keystrokes.
        if let decoded = try? container.decodeIfPresent([Option].self, forKey: .options) {
            let labels = decoded.compactMap(\.label)
            options = labels.count == decoded.count ? labels : nil
        } else {
            options = nil
        }
    }
}

public struct ToolInputSummary: Decodable, Sendable {
    public let command: String?
    public let filePath: String?
    public let description: String?
    public let questions: [QuestionSummary]?

    public init(command: String?, filePath: String?, description: String?, questions: [QuestionSummary]? = nil) {
        self.command = command
        self.filePath = filePath
        self.description = description
        self.questions = questions
    }

    enum CodingKeys: String, CodingKey {
        case command
        case filePath = "file_path"
        case description
        case questions
    }

    // MCP tools may send any shape; a mistyped field must not drop the event.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        command = try? container.decodeIfPresent(String.self, forKey: .command)
        filePath = try? container.decodeIfPresent(String.self, forKey: .filePath)
        description = try? container.decodeIfPresent(String.self, forKey: .description)
        questions = try? container.decodeIfPresent([QuestionSummary].self, forKey: .questions)
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
