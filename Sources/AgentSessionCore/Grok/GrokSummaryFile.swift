import Foundation

/// Codable subset of Grok `summary.json`.
struct GrokSummaryFile: Sendable, Equatable {
    var id: String?
    var cwd: String?
    var sessionSummary: String?
    var createdAt: Date?
    var updatedAt: Date?
    var numMessages: Int?
    var numChatMessages: Int?
    var currentModelId: String?
    var agentName: String?

    static func load(from url: URL) throws -> GrokSummaryFile {
        let data = try Data(contentsOf: url)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let info = obj["info"] as? [String: Any] ?? [:]

        return GrokSummaryFile(
            id: info["id"] as? String,
            cwd: info["cwd"] as? String,
            sessionSummary: obj["session_summary"] as? String,
            createdAt: parseDate(obj["created_at"]),
            updatedAt: parseDate(obj["updated_at"]),
            numMessages: obj["num_messages"] as? Int,
            numChatMessages: obj["num_chat_messages"] as? Int,
            currentModelId: obj["current_model_id"] as? String,
            agentName: obj["agent_name"] as? String
        )
    }

    private static func parseDate(_ value: Any?) -> Date? {
        guard let s = value as? String else { return nil }
        return ISO8601DateFormatter.fractional.date(from: s)
            ?? ISO8601DateFormatter().date(from: s)
    }
}

extension ISO8601DateFormatter {
    static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
