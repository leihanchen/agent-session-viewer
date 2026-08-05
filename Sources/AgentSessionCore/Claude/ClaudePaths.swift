import Foundation

enum ClaudePaths {
    /// Decode Claude project folder name (e.g. `-Users-mac-foo`) into a path.
    /// Prefer JSONL `cwd` when available; this is a best-effort fallback.
    static func decodeProjectPath(encodedName: String) -> String {
        var name = encodedName
        if name.hasPrefix("-") {
            name.removeFirst()
        }
        // Claude uses `-` for `/` in absolute paths on Unix.
        if !name.hasPrefix("/") {
            name = "/" + name.replacingOccurrences(of: "-", with: "/")
        }
        // The simple replace can over-replace hyphens in real path segments.
        // Callers should override with cwd from session JSONL when present.
        return name
    }

    static func displayName(forPath path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent
        if name.isEmpty || name == "/" { return path }
        return name
    }
}
