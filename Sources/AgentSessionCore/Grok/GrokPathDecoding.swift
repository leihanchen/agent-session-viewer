import Foundation

enum GrokPathDecoding {
    /// Decode a Grok sessions group folder name (percent-encoded cwd) into a path.
    static func decodeProjectPath(encodedName: String) -> String {
        if let decoded = encodedName.removingPercentEncoding, !decoded.isEmpty {
            return decoded
        }
        return encodedName
    }

    static func displayName(forPath path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent
        if name.isEmpty || name == "/" {
            return path
        }
        // Leading-dot folders like `.grok` stay as-is.
        return name
    }
}
