import Foundation

public enum DataRoot {
    /// Resolve data root for an agent.
    /// Priority: explicit override → agent env vars → default home subdirectory.
    public static func resolve(
        agent: AgentKind,
        override: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL {
        if let override, !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        }
        switch agent {
        case .grokBuild:
            if let home = environment["GROK_HOME"], !home.isEmpty {
                return URL(fileURLWithPath: (home as NSString).expandingTildeInPath, isDirectory: true)
            }
            return fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".grok", isDirectory: true)
        case .claudeCode:
            if let home = environment["CLAUDE_CONFIG_DIR"], !home.isEmpty {
                return URL(fileURLWithPath: (home as NSString).expandingTildeInPath, isDirectory: true)
            }
            if let home = environment["CLAUDE_HOME"], !home.isEmpty {
                return URL(fileURLWithPath: (home as NSString).expandingTildeInPath, isDirectory: true)
            }
            return fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".claude", isDirectory: true)
        case .codex:
            if let home = environment["CODEX_HOME"], !home.isEmpty {
                return URL(fileURLWithPath: (home as NSString).expandingTildeInPath, isDirectory: true)
            }
            return fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
        case .warp:
            if let home = environment["WARP_HOME"], !home.isEmpty {
                return warpRootURL(from: home)
            }
            if let home = environment["WARP_DIR"], !home.isEmpty {
                return warpRootURL(from: home)
            }
            return defaultWarpDataRoot(fileManager: fileManager)
        }
    }

    /// Directory that contains `warp.sqlite` (macOS group container; Linux XDG state).
    public static func defaultWarpDataRoot(fileManager: FileManager = .default) -> URL {
        let home = fileManager.homeDirectoryForCurrentUser
        #if os(macOS)
        return home.appendingPathComponent(
            "Library/Group Containers/2BBY89MBSN.dev.warp/Library/Application Support/dev.warp.Warp-Stable",
            isDirectory: true
        )
        #else
        return home.appendingPathComponent(".local/state/warp-terminal", isDirectory: true)
        #endif
    }

    /// Accept a directory or a path to `warp.sqlite`.
    public static func warpRootURL(from raw: String) -> URL {
        let expanded = (raw as NSString).expandingTildeInPath
        if expanded.hasSuffix(".sqlite") {
            return URL(fileURLWithPath: expanded).deletingLastPathComponent()
        }
        return URL(fileURLWithPath: expanded, isDirectory: true)
    }

    /// Backward-compatible Grok-only resolve.
    public static func resolve(
        override: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL {
        resolve(agent: .grokBuild, override: override, environment: environment, fileManager: fileManager)
    }

    public static func sessionsDirectory(dataRoot: URL) -> URL {
        dataRoot.appendingPathComponent("sessions", isDirectory: true)
    }

    public static func claudeProjectsDirectory(dataRoot: URL) -> URL {
        dataRoot.appendingPathComponent("projects", isDirectory: true)
    }

    public static func codexSessionsDirectory(dataRoot: URL) -> URL {
        dataRoot.appendingPathComponent("sessions", isDirectory: true)
    }
}
