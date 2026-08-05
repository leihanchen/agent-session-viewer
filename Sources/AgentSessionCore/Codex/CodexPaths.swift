import Foundation

enum CodexPaths {
    static func sessionsDirectory(dataRoot: URL) -> URL {
        DataRoot.codexSessionsDirectory(dataRoot: dataRoot)
    }

    /// Parse session UUID from `rollout-2026-07-27T10-01-19-<uuid>.jsonl`.
    static func sessionId(fromRolloutFilename name: String) -> String? {
        let base = (name as NSString).deletingPathExtension
        guard base.hasPrefix("rollout-") else { return nil }
        // UUID is last 36 chars if standard, or after last timestamp segment.
        // Pattern: rollout-<iso-ish>-<uuid>
        let parts = base.split(separator: "-")
        // uuid parts: 8-4-4-4-12 = 5 segments at end
        guard parts.count >= 6 else { return nil }
        let uuidParts = parts.suffix(5)
        let candidate = uuidParts.joined(separator: "-")
        if candidate.count == 36 { return candidate }
        return nil
    }

    static func displayName(forPath path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent
        if name.isEmpty || name == "/" { return path }
        return name
    }

    /// Stable project id from cwd (path-safe).
    static func projectId(forCwd cwd: String) -> String {
        cwd.replacingOccurrences(of: "/", with: "-")
    }

    static func isNoiseUserText(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return true }
        let markers = [
            "<permissions",
            "<recommended_plugins",
            "<multi_agent_mode",
            "<environment_context",
            "You are Codex",
            "You are `/root`",
            "Filesystem sandboxing defines which files",
        ]
        return markers.contains { t.hasPrefix($0) || t.contains($0) }
    }
}
