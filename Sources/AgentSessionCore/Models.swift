import Foundation

/// Coding-agent identifier used in exports and catalogs.
public enum AgentKind: String, Sendable, Codable, Equatable {
    case grokBuild = "grok-build"
}

/// A working-directory group that owns zero or more sessions.
public struct Project: Identifiable, Sendable, Equatable, Codable {
    /// Stable id (encoded directory name under `sessions/`).
    public var id: String
    /// Decoded working directory path when known.
    public var path: String
    /// Short label for UI lists (last path component).
    public var displayName: String
    public var sessionCount: Int
    public var lastUpdated: Date?
    public var directoryPath: String

    public init(
        id: String,
        path: String,
        displayName: String,
        sessionCount: Int,
        lastUpdated: Date?,
        directoryPath: String
    ) {
        self.id = id
        self.path = path
        self.displayName = displayName
        self.sessionCount = sessionCount
        self.lastUpdated = lastUpdated
        self.directoryPath = directoryPath
    }
}

/// Index row for one agent conversation.
public struct SessionInfo: Identifiable, Sendable, Equatable, Codable {
    public var id: String
    public var agent: AgentKind
    public var title: String
    public var projectId: String
    public var projectPath: String
    public var createdAt: Date?
    public var updatedAt: Date?
    public var messageCount: Int
    public var model: String?
    public var directoryPath: String
    public var rawSummary: String?

    public init(
        id: String,
        agent: AgentKind = .grokBuild,
        title: String,
        projectId: String,
        projectPath: String,
        createdAt: Date?,
        updatedAt: Date?,
        messageCount: Int,
        model: String?,
        directoryPath: String,
        rawSummary: String?
    ) {
        self.id = id
        self.agent = agent
        self.title = title
        self.projectId = projectId
        self.projectPath = projectPath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messageCount = messageCount
        self.model = model
        self.directoryPath = directoryPath
        self.rawSummary = rawSummary
    }
}

/// Normalized conversation event (export / detail stream).
public struct SessionEvent: Identifiable, Sendable, Equatable, Codable {
    public var id: String
    public var type: String
    public var timestamp: Date?
    public var role: String?
    public var content: String?
    public var toolName: String?
    public var toolCallId: String?
    public var isError: Bool
    /// Agent-specific payload preserved for full-trace / export.
    public var raw: [String: JSONValue]

    public init(
        id: String,
        type: String,
        timestamp: Date? = nil,
        role: String? = nil,
        content: String? = nil,
        toolName: String? = nil,
        toolCallId: String? = nil,
        isError: Bool = false,
        raw: [String: JSONValue] = [:]
    ) {
        self.id = id
        self.type = type
        self.timestamp = timestamp
        self.role = role
        self.content = content
        self.toolName = toolName
        self.toolCallId = toolCallId
        self.isError = isError
        self.raw = raw
    }
}

/// Minimal JSON-compatible value tree for preserving raw fields.
public enum JSONValue: Sendable, Equatable, Codable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let i = try? container.decode(Int.self) {
            self = .number(Double(i))
        } else if let d = try? container.decode(Double.self) {
            self = .number(d)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let a = try? container.decode([JSONValue].self) {
            self = .array(a)
        } else if let o = try? container.decode([String: JSONValue].self) {
            self = .object(o)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let b):
            try container.encode(b)
        case .number(let n):
            try container.encode(n)
        case .string(let s):
            try container.encode(s)
        case .array(let a):
            try container.encode(a)
        case .object(let o):
            try container.encode(o)
        }
    }
}
