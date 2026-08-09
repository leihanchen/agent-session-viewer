import Foundation

/// Result of permanently removing one session’s on-disk artifacts.
public struct SessionDeleteResult: Sendable, Equatable {
    public let sessionId: String
    public let agent: AgentKind
    public let deletedPath: String

    public init(sessionId: String, agent: AgentKind, deletedPath: String) {
        self.sessionId = sessionId
        self.agent = agent
        self.deletedPath = deletedPath
    }
}

/// Whether the session path must be a directory (Grok) or a regular file (Claude/Codex).
public enum SessionDeletePathKind: Sendable, Equatable {
    case directory
    case file
}

/// Shared safety checks + remove for agent session artifacts under a data root.
public enum SessionDeleter {
    /// Delete `session.directoryPath` after verifying it lives under `dataRoot` and matches `pathKind`.
    public static func delete(
        session: SessionInfo,
        dataRoot: URL,
        pathKind: SessionDeletePathKind,
        fileManager: FileManager = .default
    ) throws -> SessionDeleteResult {
        let root = standardize(dataRoot)
        let target = standardize(URL(fileURLWithPath: session.directoryPath))

        guard isStrictlyUnder(child: target, parent: root) else {
            throw AgentCatalogError.pathOutsideDataRoot(target.path)
        }

        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: target.path, isDirectory: &isDir) else {
            throw AgentCatalogError.pathMissing(target.path)
        }

        switch pathKind {
        case .directory:
            guard isDir.boolValue else {
                throw AgentCatalogError.deleteFailed(
                    target.path,
                    "Expected a session directory, found a file"
                )
            }
        case .file:
            guard !isDir.boolValue else {
                throw AgentCatalogError.deleteFailed(
                    target.path,
                    "Expected a session file, found a directory"
                )
            }
        }

        // Refuse deleting the data root itself (also covered by strictly-under).
        if target.path == root.path {
            throw AgentCatalogError.pathOutsideDataRoot(target.path)
        }

        do {
            try fileManager.removeItem(at: target)
        } catch {
            throw AgentCatalogError.deleteFailed(target.path, error.localizedDescription)
        }

        return SessionDeleteResult(
            sessionId: session.id,
            agent: session.agent,
            deletedPath: target.path
        )
    }

    // MARK: - Path helpers

    public static func standardize(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    /// True when `child` is a path strictly inside `parent` (not equal).
    public static func isStrictlyUnder(child: URL, parent: URL) -> Bool {
        let c = standardize(child).path
        let p = standardize(parent).path
        if c == p { return false }
        let prefix = p.hasSuffix("/") ? p : p + "/"
        return c.hasPrefix(prefix)
    }
}
