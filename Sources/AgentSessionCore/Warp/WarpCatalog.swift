import Foundation

/// Catalog of Warp agent conversations in `warp.sqlite`.
public struct WarpCatalog: AgentSessionStore {
    public var agent: AgentKind { .warp }
    public let dataRoot: URL
    public let databaseURL: URL

    public init(dataRoot: URL) {
        self.dataRoot = dataRoot
        self.databaseURL = WarpPaths.databaseURL(dataRoot: dataRoot)
    }

    public init(homeOverride: String? = nil) {
        let root = DataRoot.resolve(agent: .warp, override: homeOverride)
        self.init(dataRoot: root)
    }

    public func listProjects() throws -> [Project] {
        let sessions = try listSessions(projectId: nil)
        var byProject: [String: (path: String, sessions: [SessionInfo], last: Date?)] = [:]
        for s in sessions {
            var entry = byProject[s.projectId] ?? (path: s.projectPath, sessions: [], last: nil)
            entry.sessions.append(s)
            if let u = s.updatedAt {
                if entry.last == nil || u > entry.last! { entry.last = u }
            }
            byProject[s.projectId] = entry
        }
        return byProject.map { id, entry in
            Project(
                id: id,
                path: entry.path,
                displayName: WarpPaths.displayName(forPath: entry.path),
                sessionCount: entry.sessions.count,
                lastUpdated: entry.last,
                directoryPath: entry.path
            )
        }
        .sorted { lhs, rhs in
            switch (lhs.lastUpdated, rhs.lastUpdated) {
            case let (l?, r?):
                if l != r { return l > r }
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): break
            }
            return lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
        }
    }

    public func listSessions(projectId: String? = nil) throws -> [SessionInfo] {
        try ensureDatabase()
        let db = try WarpSQLite(databaseURL: databaseURL, readOnly: true)
        let rows = try db.query(
            """
            SELECT conversation_id, summary, conversation_data, last_modified_at
            FROM agent_conversations
            """
        )
        let stats = try queryStats(db)
        var sessions: [SessionInfo] = []
        for row in rows {
            guard let info = sessionInfo(row: row, stats: stats[row["conversation_id"] ?? ""]) else {
                continue
            }
            if let projectId, info.projectId != projectId { continue }
            sessions.append(info)
        }
        return sessions.sorted { lhs, rhs in
            switch (lhs.updatedAt, rhs.updatedAt) {
            case let (l?, r?):
                if l != r { return l > r }
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): break
            }
            return lhs.id < rhs.id
        }
    }

    public func session(id sessionId: String) throws -> SessionInfo {
        try ensureDatabase()
        let db = try WarpSQLite(databaseURL: databaseURL, readOnly: true)
        let rows = try db.query(
            """
            SELECT conversation_id, summary, conversation_data, last_modified_at
            FROM agent_conversations
            WHERE conversation_id = ?
            LIMIT 1
            """,
            binds: [sessionId]
        )
        guard let row = rows.first else {
            throw AgentCatalogError.sessionNotFound(sessionId)
        }
        let stats = try queryStats(db, conversationId: sessionId)
        guard let info = sessionInfo(row: row, stats: stats[sessionId]) else {
            throw AgentCatalogError.sessionNotFound(sessionId)
        }
        return info
    }

    public func loadEvents(session: SessionInfo) throws -> [SessionEvent] {
        try WarpTranscript.loadEvents(locator: session.directoryPath)
    }

    /// SQL-only delete of one conversation. Never removes `warp.sqlite`.
    public func deleteSession(id sessionId: String) throws -> SessionDeleteResult {
        _ = try session(id: sessionId)
        try ensureDatabase()
        let db = try WarpSQLite(databaseURL: databaseURL, readOnly: false)
        try db.transaction {
            try deleteIfTableExists(db, table: "agent_tasks", conversationId: sessionId)
            try deleteIfTableExists(db, table: "ai_queries", conversationId: sessionId)
            try db.execute("DELETE FROM agent_conversations WHERE conversation_id = ?", binds: [sessionId])
        }
        return SessionDeleteResult(
            sessionId: sessionId,
            agent: .warp,
            deletedPath: WarpPaths.locator(database: databaseURL, conversationId: sessionId)
        )
    }

    // MARK: - Internals

    private func deleteIfTableExists(_ db: WarpSQLite, table: String, conversationId: String) throws {
        do {
            try db.execute("DELETE FROM \(table) WHERE conversation_id = ?", binds: [conversationId])
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            if message.contains("no such table") { return }
            throw error
        }
    }

    private func ensureDatabase() throws {
        var isDir: ObjCBool = false
        if !FileManager.default.fileExists(atPath: dataRoot.path, isDirectory: &isDir) || !isDir.boolValue {
            throw AgentCatalogError.dataRootMissing(dataRoot.path)
        }
        if !FileManager.default.fileExists(atPath: databaseURL.path) {
            throw AgentCatalogError.sessionsDirMissing(databaseURL.path)
        }
    }

    private struct QueryStats {
        var count: Int
        var firstTs: Date?
        var model: String?
        var cwd: String?
    }

    private func queryStats(_ db: WarpSQLite, conversationId: String? = nil) throws -> [String: QueryStats] {
        let sql: String
        let binds: [String]
        if let conversationId {
            sql = """
            SELECT conversation_id, start_ts, model_id, working_directory
            FROM ai_queries
            WHERE conversation_id = ?
            ORDER BY start_ts ASC
            """
            binds = [conversationId]
        } else {
            sql = """
            SELECT conversation_id, start_ts, model_id, working_directory
            FROM ai_queries
            ORDER BY start_ts ASC
            """
            binds = []
        }
        let rows: [[String: String]]
        do {
            rows = try db.query(sql, binds: binds)
        } catch {
            // Older / fixture DBs may omit ai_queries.
            return [:]
        }
        var out: [String: QueryStats] = [:]
        for row in rows {
            guard let id = row["conversation_id"], !id.isEmpty else { continue }
            var stat = out[id] ?? QueryStats(count: 0, firstTs: nil, model: nil, cwd: nil)
            stat.count += 1
            if stat.firstTs == nil {
                stat.firstTs = WarpTranscript.parseTimestamp(row["start_ts"])
            }
            if stat.model == nil, let m = row["model_id"], !m.isEmpty, m != "\"\"" {
                stat.model = m.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
            if stat.cwd == nil, let cwd = row["working_directory"], !cwd.isEmpty {
                stat.cwd = cwd
            }
            out[id] = stat
        }
        return out
    }

    private func sessionInfo(row: [String: String], stats: QueryStats?) -> SessionInfo? {
        guard let id = row["conversation_id"], !id.isEmpty else { return nil }
        let summary = WarpTranscript.parseSummary(row["summary"])
        let cwd = summary.cwd ?? stats?.cwd ?? ""
        let projectPath = cwd.isEmpty ? "(unknown)" : cwd
        let title = SessionTitle.resolve(
            sessionId: id,
            summary: summary.title,
            firstUserMessage: summary.initialQuery
        )
        let model = stats?.model ?? WarpTranscript.parseModel(fromConversationData: row["conversation_data"])
        return SessionInfo(
            id: id,
            agent: .warp,
            title: title,
            projectId: WarpPaths.projectId(forCwd: projectPath),
            projectPath: projectPath,
            createdAt: stats?.firstTs,
            updatedAt: WarpTranscript.parseTimestamp(row["last_modified_at"]),
            messageCount: stats?.count ?? (summary.initialQuery == nil ? 0 : 1),
            model: model,
            directoryPath: WarpPaths.locator(database: databaseURL, conversationId: id),
            rawSummary: summary.title ?? summary.initialQuery
        )
    }
}
