import Foundation

/// Discovery, transcript load, and confirmed session delete for one coding agent.
public protocol AgentSessionStore {
    var agent: AgentKind { get }
    var dataRoot: URL { get }

    func listProjects() throws -> [Project]
    func listSessions(projectId: String?) throws -> [SessionInfo]
    func session(id: String) throws -> SessionInfo
    func loadEvents(session: SessionInfo) throws -> [SessionEvent]
    /// Permanently remove session artifacts under the data root. Irreversible.
    func deleteSession(id: String) throws -> SessionDeleteResult
}

public enum AgentStoreFactory {
    public static func make(agent: AgentKind, homeOverride: String? = nil) -> any AgentSessionStore {
        switch agent {
        case .grokBuild:
            return GrokCatalog(homeOverride: homeOverride)
        case .claudeCode:
            return ClaudeCatalog(homeOverride: homeOverride)
        case .codex:
            return CodexCatalog(homeOverride: homeOverride)
        case .warp:
            return WarpCatalog(homeOverride: homeOverride)
        }
    }
}

public enum AgentCatalogError: Error, LocalizedError, Equatable {
    case dataRootMissing(String)
    case sessionsDirMissing(String)
    case sessionNotFound(String)
    case pathOutsideDataRoot(String)
    case pathMissing(String)
    case deleteFailed(String, String)

    public var errorDescription: String? {
        switch self {
        case .dataRootMissing(let path):
            return "Data root does not exist: \(path)"
        case .sessionsDirMissing(let path):
            return "Sessions directory does not exist: \(path)"
        case .sessionNotFound(let id):
            return "Session not found: \(id)"
        case .pathOutsideDataRoot(let path):
            return "Refusing to delete path outside data root: \(path)"
        case .pathMissing(let path):
            return "Session path no longer exists: \(path)"
        case .deleteFailed(let path, let message):
            return "Failed to delete \(path): \(message)"
        }
    }
}
