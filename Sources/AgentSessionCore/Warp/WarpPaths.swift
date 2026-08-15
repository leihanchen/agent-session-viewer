import Foundation

enum WarpPaths {
    static func databaseURL(dataRoot: URL) -> URL {
        if dataRoot.pathExtension == "sqlite" {
            return dataRoot
        }
        return dataRoot.appendingPathComponent("warp.sqlite")
    }

    static func locator(database: URL, conversationId: String) -> String {
        "\(database.path)#\(conversationId)"
    }

    static func parseLocator(_ locator: String) -> (database: URL, conversationId: String)? {
        guard let hash = locator.lastIndex(of: "#") else { return nil }
        let path = String(locator[..<hash])
        let id = String(locator[locator.index(after: hash)...])
        guard !path.isEmpty, !id.isEmpty else { return nil }
        return (URL(fileURLWithPath: path), id)
    }

    static func projectId(forCwd cwd: String) -> String {
        cwd.replacingOccurrences(of: "/", with: "-")
    }

    static func displayName(forPath path: String) -> String {
        if path.isEmpty { return "(unknown)" }
        let name = URL(fileURLWithPath: path).lastPathComponent
        if name.isEmpty || name == "/" { return path }
        return name
    }
}
