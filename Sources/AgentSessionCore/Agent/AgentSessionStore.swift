import Foundation

/// Read-only discovery + transcript load for one coding agent.
public protocol AgentSessionStore {
    var agent: AgentKind { get }
    var dataRoot: URL { get }

    func listProjects() throws -> [Project]
    func listSessions(projectId: String?) throws -> [SessionInfo]
    func session(id: String) throws -> SessionInfo
    func loadEvents(session: SessionInfo) throws -> [SessionEvent]
}

public enum AgentStoreFactory {
    public static func make(agent: AgentKind, homeOverride: String? = nil) -> any AgentSessionStore {
        switch agent {
        case .grokBuild:
            return GrokCatalog(homeOverride: homeOverride)
        case .claudeCode:
            return ClaudeCatalog(homeOverride: homeOverride)
        }
    }
}

public enum AgentCatalogError: Error, LocalizedError, Equatable {
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
