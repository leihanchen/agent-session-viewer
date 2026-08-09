import Foundation

/// Read-only catalog of OpenAI Codex sessions under `~/.codex/sessions`.
public struct CodexCatalog: AgentSessionStore {
    public var agent: AgentKind { .codex }
    public let dataRoot: URL
    private let fileManager: FileManager
    private var indexTitles: [String: String] = [:]

    public init(dataRoot: URL, fileManager: FileManager = .default) {
        self.dataRoot = dataRoot
        self.fileManager = fileManager
        self.indexTitles = Self.loadIndexTitles(dataRoot: dataRoot)
    }

    public init(homeOverride: String? = nil, fileManager: FileManager = .default) {
        let root = DataRoot.resolve(agent: .codex, override: homeOverride, fileManager: fileManager)
        self.init(dataRoot: root, fileManager: fileManager)
    }

    public var sessionsURL: URL {
        CodexPaths.sessionsDirectory(dataRoot: dataRoot)
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
                displayName: CodexPaths.displayName(forPath: entry.path),
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
        try ensureSessionsDir()
        let files = try rolloutFiles()
        var sessions: [SessionInfo] = []
        for file in files {
            guard let info = try? loadSessionInfo(jsonl: file) else { continue }
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
        try ensureSessionsDir()
        for file in try rolloutFiles() {
            if let sid = CodexPaths.sessionId(fromRolloutFilename: file.lastPathComponent),
               sid == sessionId
            {
                return try loadSessionInfo(jsonl: file)
            }
            // Also match by scanning meta if filename parse fails
            let meta = CodexTranscript.loadMeta(from: file, indexTitle: indexTitles[sessionId])
            if meta.sessionId == sessionId {
                return try loadSessionInfo(jsonl: file)
            }
        }
        throw AgentCatalogError.sessionNotFound(sessionId)
    }

    public func loadEvents(session: SessionInfo) throws -> [SessionEvent] {
        let url = URL(fileURLWithPath: session.directoryPath)
        return try CodexTranscript.loadEvents(from: url)
    }

    public func deleteSession(id sessionId: String) throws -> SessionDeleteResult {
        let session = try session(id: sessionId)
        return try SessionDeleter.delete(
            session: session,
            dataRoot: dataRoot,
            pathKind: .file,
            fileManager: fileManager
        )
    }

    // MARK: - Internals

    private func ensureSessionsDir() throws {
        var isDir: ObjCBool = false
        if !fileManager.fileExists(atPath: dataRoot.path, isDirectory: &isDir) || !isDir.boolValue {
            throw AgentCatalogError.dataRootMissing(dataRoot.path)
        }
        if !fileManager.fileExists(atPath: sessionsURL.path, isDirectory: &isDir) || !isDir.boolValue {
            throw AgentCatalogError.sessionsDirMissing(sessionsURL.path)
        }
    }

    private func rolloutFiles() throws -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: sessionsURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            if name.hasPrefix("rollout-"), name.hasSuffix(".jsonl") {
                files.append(url)
            }
        }
        return files
    }

    private func loadSessionInfo(jsonl: URL) throws -> SessionInfo {
        let sidFromName = CodexPaths.sessionId(fromRolloutFilename: jsonl.lastPathComponent)
        let meta = CodexTranscript.loadMeta(
            from: jsonl,
            indexTitle: sidFromName.flatMap { indexTitles[$0] }
        )
        let sessionId = meta.sessionId ?? sidFromName ?? jsonl.deletingPathExtension().lastPathComponent
        let cwd = meta.cwd ?? "(unknown)"
        let projectId = CodexPaths.projectId(forCwd: cwd)
        let title = SessionTitle.resolve(
            sessionId: sessionId,
            summary: meta.title,
            firstUserMessage: meta.firstUserMessage
        )
        return SessionInfo(
            id: sessionId,
            agent: .codex,
            title: title,
            projectId: projectId,
            projectPath: cwd,
            createdAt: meta.createdAt,
            updatedAt: meta.updatedAt,
            messageCount: meta.messageCount,
            model: meta.model,
            directoryPath: jsonl.path,
            rawSummary: meta.title
        )
    }

    private static func loadIndexTitles(dataRoot: URL) -> [String: String] {
        let url = dataRoot.appendingPathComponent("session_index.jsonl")
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8)
        else { return [:] }
        var map: [String: String] = [:]
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let id = obj["id"] as? String,
                  let name = obj["thread_name"] as? String,
                  !name.isEmpty
            else { continue }
            map[id] = name
        }
        return map
    }
}
