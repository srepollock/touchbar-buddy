import Foundation

public enum SessionState: String, Codable, Sendable, CaseIterable {
    case needsInput = "needs_input"
    case working
    case finished
    case idle
}

public enum SpeechKind: String, Codable, Sendable {
    case permission
    case question
    case working
    case finished
    case idle
    case allClear = "all_clear"
}

public struct SessionRecord: Codable, Equatable, Sendable {
    public var sessionID: String
    public var cwd: String
    public var projectName: String
    public var state: SessionState
    public var speechKind: SpeechKind
    public var detail: String?
    public var toolName: String?
    public var updatedAt: Date
    public var startedAt: Date
    public var claudePID: Int32?
    public var itermSessionID: String?
    public var entrypoint: String?
    public var pendingQuestion: String?
    public var pendingOptions: [String]?
    public var pendingToolUseID: String?
    /// Tool calls with a PreToolUse and no PostToolUse yet; nil means none. Optional so old session files decode.
    public var inFlightToolUseIDs: [String]?
    /// True when a PermissionRequest hook named the tool behind this prompt (authoritative identity).
    public var permissionRequestConfirmed: Bool?

    public init(
        sessionID: String,
        cwd: String,
        projectName: String,
        state: SessionState,
        speechKind: SpeechKind,
        detail: String? = nil,
        toolName: String? = nil,
        updatedAt: Date,
        startedAt: Date,
        claudePID: Int32? = nil,
        itermSessionID: String? = nil,
        entrypoint: String? = nil,
        pendingQuestion: String? = nil,
        pendingOptions: [String]? = nil,
        pendingToolUseID: String? = nil,
        inFlightToolUseIDs: [String]? = nil,
        permissionRequestConfirmed: Bool? = nil
    ) {
        self.sessionID = sessionID
        self.cwd = cwd
        self.projectName = projectName
        self.state = state
        self.speechKind = speechKind
        self.detail = detail
        self.toolName = toolName
        self.updatedAt = updatedAt
        self.startedAt = startedAt
        self.claudePID = claudePID
        self.itermSessionID = itermSessionID
        self.entrypoint = entrypoint
        self.pendingQuestion = pendingQuestion
        self.pendingOptions = pendingOptions
        self.pendingToolUseID = pendingToolUseID
        self.inFlightToolUseIDs = inFlightToolUseIDs
        self.permissionRequestConfirmed = permissionRequestConfirmed
    }
}
