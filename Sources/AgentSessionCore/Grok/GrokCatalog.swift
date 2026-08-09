import Foundation

public enum GrokCatalogError: Error, LocalizedError, Equatable {
    case dataRootMissing(String)
    case sessionsDirMissing(String)
    case sessionNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .dataRootMissing(let path):
            return "Data root does not exist: \(path)"
        case .sessionsDirMissing(let path):
            return "Sessions directory does not exist: \(path)"
        case .sessionNotFound(let id):
            return "Session not found: \(id)"
        }
    }
}

/// Read-only catalog of Grok Build projects and sessions under a Data root.
public struct GrokCatalog: AgentSessionStore {
    public var agent: AgentKind { .grokBuild }
    public let dataRoot: URL
    private let fileManager: FileManager

    public init(dataRoot: URL, fileManager: FileManager = .default) {
        self.dataRoot = dataRoot
        self.fileManager = fileManager
    }

    public init(homeOverride: String? = nil, fileManager: FileManager = .default) {
        self.dataRoot = DataRoot.resolve(agent: .grokBuild, override: homeOverride, fileManager: fileManager)
        self.fileManager = fileManager
    }

    public func loadEvents(session: SessionInfo) throws -> [SessionEvent] {
        let dir = URL(fileURLWithPath: session.directoryPath, isDirectory: true)
        return try GrokUpdates.loadEvents(sessionDirectory: dir)
    }

    public func deleteSession(id sessionId: String) throws -> SessionDeleteResult {
        let session = try session(id: sessionId)
        return try SessionDeleter.delete(
            session: session,
            dataRoot: dataRoot,
            pathKind: .directory,
            fileManager: fileManager
        )
    }

    public var sessionsURL: URL {
        DataRoot.sessionsDirectory(dataRoot: dataRoot)
    }

    public func listProjects() throws -> [Project] {
        try ensureSessionsDir()
        let projectDirs = try projectDirectories()
        var projects: [Project] = []

        for dir in projectDirs {
            let sessions = try sessionDirectories(in: dir)
            var lastUpdated: Date?
            for sessionDir in sessions {
                if let summaryURL = summaryURL(in: sessionDir),
                   let summary = try? GrokSummaryFile.load(from: summaryURL),
                   let updated = summary.updatedAt
                {
                    if lastUpdated == nil || updated > lastUpdated! {
                        lastUpdated = updated
                    }
                } else if let attrs = try? fileManager.attributesOfItem(atPath: sessionDir.path),
                          let mod = attrs[.modificationDate] as? Date
                {
                    if lastUpdated == nil || mod > lastUpdated! {
                        lastUpdated = mod
                    }
                }
            }

            let encoded = dir.lastPathComponent
            let path = GrokPathDecoding.decodeProjectPath(encodedName: encoded)
            projects.append(
                Project(
                    id: encoded,
                    path: path,
                    displayName: GrokPathDecoding.displayName(forPath: path),
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
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                break
            }
            return lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
        }
    }

    public func listSessions(projectId: String? = nil) throws -> [SessionInfo] {
        try ensureSessionsDir()
        let projectDirs: [URL]
        if let projectId {
            let dir = sessionsURL.appendingPathComponent(projectId, isDirectory: true)
            guard fileManager.fileExists(atPath: dir.path) else {
                return []
            }
            projectDirs = [dir]
        } else {
            projectDirs = try projectDirectories()
        }

        var sessions: [SessionInfo] = []
        for projectDir in projectDirs {
            let encoded = projectDir.lastPathComponent
            let projectPath = GrokPathDecoding.decodeProjectPath(encodedName: encoded)
            for sessionDir in try sessionDirectories(in: projectDir) {
                if let info = try? loadSessionInfo(sessionDir: sessionDir, projectId: encoded, projectPath: projectPath) {
                    sessions.append(info)
                }
            }
        }

        return sessions.sorted { lhs, rhs in
            switch (lhs.updatedAt, rhs.updatedAt) {
            case let (l?, r?):
                if l != r { return l > r }
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                break
            }
            return lhs.id < rhs.id
        }
    }

    public func session(id sessionId: String) throws -> SessionInfo {
        try ensureSessionsDir()
        for projectDir in try projectDirectories() {
            let candidate = projectDir.appendingPathComponent(sessionId, isDirectory: true)
            if fileManager.fileExists(atPath: candidate.path) {
                let encoded = projectDir.lastPathComponent
                let projectPath = GrokPathDecoding.decodeProjectPath(encodedName: encoded)
                return try loadSessionInfo(sessionDir: candidate, projectId: encoded, projectPath: projectPath)
            }
        }
        throw AgentCatalogError.sessionNotFound(sessionId)
    }

    // MARK: - Internals

    private func ensureSessionsDir() throws {
        var isDir: ObjCBool = false
        if !fileManager.fileExists(atPath: dataRoot.path, isDirectory: &isDir) || !isDir.boolValue {
            throw AgentCatalogError.dataRootMissing(dataRoot.path)
        }
        let sessions = sessionsURL
        if !fileManager.fileExists(atPath: sessions.path, isDirectory: &isDir) || !isDir.boolValue {
            throw AgentCatalogError.sessionsDirMissing(sessions.path)
        }
    }

    private func projectDirectories() throws -> [URL] {
        let contents = try fileManager.contentsOfDirectory(
            at: sessionsURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return contents.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
    }

    private func sessionDirectories(in projectDir: URL) throws -> [URL] {
        let contents = try fileManager.contentsOfDirectory(
            at: projectDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return contents.filter { url in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                return false
            }
            // A session dir should contain summary.json and/or updates.jsonl.
            let summary = url.appendingPathComponent("summary.json")
            let updates = url.appendingPathComponent("updates.jsonl")
            return fileManager.fileExists(atPath: summary.path) || fileManager.fileExists(atPath: updates.path)
        }
    }

    private func summaryURL(in sessionDir: URL) -> URL? {
        let url = sessionDir.appendingPathComponent("summary.json")
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    private func loadSessionInfo(sessionDir: URL, projectId: String, projectPath: String) throws -> SessionInfo {
        let sessionId = sessionDir.lastPathComponent
        var summaryText: String?
        var createdAt: Date?
        var updatedAt: Date?
        var messageCount = 0
        var model: String?
        var cwd = projectPath

        if let summaryURL = summaryURL(in: sessionDir) {
            let file = try GrokSummaryFile.load(from: summaryURL)
            summaryText = file.sessionSummary
            createdAt = file.createdAt
            updatedAt = file.updatedAt
            messageCount = file.numChatMessages ?? file.numMessages ?? 0
            model = file.currentModelId
            if let fileCwd = file.cwd, !fileCwd.isEmpty {
                cwd = fileCwd
            }
            if let fileId = file.id, !fileId.isEmpty, fileId != sessionId {
                // Prefer directory name as id; Grok usually matches.
            }
        }

        var firstUser: String?
        let needsUserFallback = (summaryText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if needsUserFallback {
            firstUser = GrokUpdates.firstUserMessage(in: sessionDir.appendingPathComponent("updates.jsonl"))
        }

        let title = SessionTitle.resolve(
            sessionId: sessionId,
            summary: summaryText,
            firstUserMessage: firstUser
        )

        return SessionInfo(
            id: sessionId,
            agent: .grokBuild,
            title: title,
            projectId: projectId,
            projectPath: cwd,
            createdAt: createdAt,
            updatedAt: updatedAt,
            messageCount: messageCount,
            model: model,
            directoryPath: sessionDir.path,
            rawSummary: summaryText
        )
    }
}
