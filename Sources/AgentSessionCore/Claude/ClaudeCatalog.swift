import Foundation

/// Read-only catalog of Claude Code sessions under `~/.claude/projects`.
public struct ClaudeCatalog: AgentSessionStore {
    public var agent: AgentKind { .claudeCode }
    public let dataRoot: URL
    private let fileManager: FileManager

    public init(dataRoot: URL, fileManager: FileManager = .default) {
        self.dataRoot = dataRoot
        self.fileManager = fileManager
    }

    public init(homeOverride: String? = nil, fileManager: FileManager = .default) {
        self.dataRoot = DataRoot.resolve(agent: .claudeCode, override: homeOverride, fileManager: fileManager)
        self.fileManager = fileManager
    }

    public var projectsURL: URL {
        DataRoot.claudeProjectsDirectory(dataRoot: dataRoot)
    }

    public func listProjects() throws -> [Project] {
        try ensureProjectsDir()
        let dirs = try projectDirectories()
        var projects: [Project] = []
        for dir in dirs {
            let sessions = try sessionFiles(in: dir)
            guard !sessions.isEmpty else { continue }
            var lastUpdated: Date?
            var path = ClaudePaths.decodeProjectPath(encodedName: dir.lastPathComponent)
            for file in sessions {
                if let meta = optionalMeta(file), let cwd = meta.cwd, !cwd.isEmpty {
                    path = cwd
                }
                if let attrs = try? fileManager.attributesOfItem(atPath: file.path),
                   let mod = attrs[.modificationDate] as? Date
                {
                    if lastUpdated == nil || mod > lastUpdated! { lastUpdated = mod }
                }
            }
            projects.append(
                Project(
                    id: dir.lastPathComponent,
                    path: path,
                    displayName: ClaudePaths.displayName(forPath: path),
                    sessionCount: sessions.count,
                    lastUpdated: lastUpdated,
                    directoryPath: dir.path
                )
            )
        }
        return projects.sorted { lhs, rhs in
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
        try ensureProjectsDir()
        let dirs: [URL]
        if let projectId {
            let dir = projectsURL.appendingPathComponent(projectId, isDirectory: true)
            guard fileManager.fileExists(atPath: dir.path) else { return [] }
            dirs = [dir]
        } else {
            dirs = try projectDirectories()
        }
        var sessions: [SessionInfo] = []
        for dir in dirs {
            let encoded = dir.lastPathComponent
            for file in try sessionFiles(in: dir) {
                if let info = try? loadSessionInfo(jsonl: file, projectId: encoded) {
                    sessions.append(info)
                }
            }
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
        try ensureProjectsDir()
        for dir in try projectDirectories() {
            let candidate = dir.appendingPathComponent("\(sessionId).jsonl")
            if fileManager.fileExists(atPath: candidate.path) {
                return try loadSessionInfo(jsonl: candidate, projectId: dir.lastPathComponent)
            }
        }
        throw AgentCatalogError.sessionNotFound(sessionId)
    }

    public func loadEvents(session: SessionInfo) throws -> [SessionEvent] {
        // directoryPath for Claude is the jsonl file path.
        let url = URL(fileURLWithPath: session.directoryPath)
        return try ClaudeTranscript.loadEventsExpanded(from: url)
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

    private func ensureProjectsDir() throws {
        var isDir: ObjCBool = false
        if !fileManager.fileExists(atPath: dataRoot.path, isDirectory: &isDir) || !isDir.boolValue {
            throw AgentCatalogError.dataRootMissing(dataRoot.path)
        }
        if !fileManager.fileExists(atPath: projectsURL.path, isDirectory: &isDir) || !isDir.boolValue {
            throw AgentCatalogError.sessionsDirMissing(projectsURL.path)
        }
    }

    private func projectDirectories() throws -> [URL] {
        let contents = try fileManager.contentsOfDirectory(
            at: projectsURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return contents.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    }

    private func sessionFiles(in projectDir: URL) throws -> [URL] {
        let contents = try fileManager.contentsOfDirectory(
            at: projectDir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        return contents.filter { $0.pathExtension == "jsonl" }
    }

    private func optionalMeta(_ file: URL) -> ClaudeTranscript.SessionMeta? {
        ClaudeTranscript.loadMeta(from: file)
    }

    private func loadSessionInfo(jsonl: URL, projectId: String) throws -> SessionInfo {
        let sessionId = jsonl.deletingPathExtension().lastPathComponent
        let meta = ClaudeTranscript.loadMeta(from: jsonl)
        let projectPath = meta.cwd ?? ClaudePaths.decodeProjectPath(encodedName: projectId)
        let title = SessionTitle.resolve(
            sessionId: sessionId,
            summary: meta.title,
            firstUserMessage: meta.firstUserMessage
        )
        return SessionInfo(
            id: sessionId,
            agent: .claudeCode,
            title: title,
            projectId: projectId,
            projectPath: projectPath,
            createdAt: meta.createdAt,
            updatedAt: meta.updatedAt,
            messageCount: meta.messageCount,
            model: meta.model,
            directoryPath: jsonl.path,
            rawSummary: meta.title
        )
    }
}
