import Foundation

/// Portable normalized export document (one session).
public struct ExportBundle: Sendable, Equatable, Codable {
    public var schemaVersion: Int
    public var agent: AgentKind
    public var exportedAt: Date
    public var session: SessionInfo
    public var events: [SessionEvent]

    public init(
        schemaVersion: Int = 1,
        agent: AgentKind,
        exportedAt: Date = Date(),
        session: SessionInfo,
        events: [SessionEvent]
    ) {
        self.schemaVersion = schemaVersion
        self.agent = agent
        self.exportedAt = exportedAt
        self.session = session
        self.events = events
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case agent
        case exportedAt = "exported_at"
        case session
        case events
    }
}

public enum SessionExporter {
    public static func buildBundle(session: SessionInfo) throws -> ExportBundle {
        let dir = URL(fileURLWithPath: session.directoryPath, isDirectory: true)
        let events = try GrokUpdates.loadEvents(sessionDirectory: dir)
        return ExportBundle(agent: session.agent, session: session, events: events)
    }

    /// Write one JSON file for the session into `outputDirectory`.
    @discardableResult
    public static func exportSession(
        session: SessionInfo,
        to outputDirectory: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let bundle = try buildBundle(session: session)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(bundle)
        let safeName = session.id.replacingOccurrences(of: "/", with: "_")
        let fileURL = outputDirectory.appendingPathComponent("\(safeName).json")
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }
}
