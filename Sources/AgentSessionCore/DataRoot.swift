import Foundation

public enum DataRoot {
    /// Resolve Grok home / Data root.
    /// Priority: explicit override → `GROK_HOME` → `~/.grok`.
    public static func resolve(
        override: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL {
        if let override, !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        }
        if let home = environment["GROK_HOME"], !home.isEmpty {
            return URL(fileURLWithPath: (home as NSString).expandingTildeInPath, isDirectory: true)
        }
        return fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".grok", isDirectory: true)
    }

    public static func sessionsDirectory(dataRoot: URL) -> URL {
        dataRoot.appendingPathComponent("sessions", isDirectory: true)
    }
}
