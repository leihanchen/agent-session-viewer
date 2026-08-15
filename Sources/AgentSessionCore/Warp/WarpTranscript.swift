import Foundation

/// Parse Warp `summary` / `ai_queries.input` into normalized events + catalog fields.
enum WarpTranscript {
    struct Summary: Sendable {
        var title: String?
        var initialQuery: String?
        var cwd: String?
    }

    static func parseSummary(_ raw: String?) -> Summary {
        guard let raw, let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return Summary()
        }
        return Summary(
            title: stringValue(obj["title"]),
            initialQuery: stringValue(obj["initial_query"]),
            cwd: stringValue(obj["initial_working_directory"])
        )
    }

    static func parseModel(fromConversationData raw: String?) -> String? {
        guard let raw, let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let meta = obj["conversation_usage_metadata"] as? [String: Any],
              let usage = meta["token_usage"] as? [[String: Any]]
        else {
            return nil
        }
        return usage.compactMap { stringValue($0["model_id"]) }.first { !$0.isEmpty }
    }

    /// Extract user-visible query texts from an `ai_queries.input` JSON array.
    static func queryTexts(fromInput raw: String) -> [String] {
        guard let data = raw.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [Any]
        else {
            return []
        }
        var texts: [String] = []
        for item in arr {
            guard let dict = item as? [String: Any],
                  let query = dict["Query"] as? [String: Any],
                  let text = stringValue(query["text"]),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { continue }
            texts.append(text)
        }
        return texts
    }

    static func loadEvents(locator: String) throws -> [SessionEvent] {
        guard let parsed = WarpPaths.parseLocator(locator) else {
            throw AgentCatalogError.sessionNotFound(locator)
        }
        return try loadEvents(databaseURL: parsed.database, conversationId: parsed.conversationId)
    }

    static func loadEvents(databaseURL: URL, conversationId: String) throws -> [SessionEvent] {
        let db = try WarpSQLite(databaseURL: databaseURL, readOnly: true)
        let summaryRows = try db.query(
            "SELECT summary FROM agent_conversations WHERE conversation_id = ? LIMIT 1",
            binds: [conversationId]
        )
        guard let summaryRow = summaryRows.first else {
            throw AgentCatalogError.sessionNotFound(conversationId)
        }
        let summary = parseSummary(summaryRow["summary"])

        let queryRows = try db.query(
            """
            SELECT exchange_id, start_ts, input
            FROM ai_queries
            WHERE conversation_id = ?
            ORDER BY start_ts ASC
            """,
            binds: [conversationId]
        )

        var events: [SessionEvent] = []
        for (index, row) in queryRows.enumerated() {
            let texts = queryTexts(fromInput: row["input"] ?? "")
            let ts = parseTimestamp(row["start_ts"])
            if texts.isEmpty {
                continue
            }
            for (j, text) in texts.enumerated() {
                events.append(
                    SessionEvent(
                        id: "\(row["exchange_id"] ?? conversationId)-\(index)-\(j)",
                        type: "user",
                        timestamp: ts,
                        role: "user",
                        content: text,
                        toolName: nil,
                        toolCallId: nil,
                        isError: false
                    )
                )
            }
        }

        if events.isEmpty, let initial = summary.initialQuery, !initial.isEmpty {
            events.append(
                SessionEvent(
                    id: "\(conversationId)-initial",
                    type: "user",
                    timestamp: nil,
                    role: "user",
                    content: initial,
                    toolName: nil,
                    toolCallId: nil,
                    isError: false
                )
            )
        }
        return events
    }

    static func parseTimestamp(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let formats = [
            "yyyy-MM-dd HH:mm:ss.SSSSSS",
            "yyyy-MM-dd HH:mm:ss.SSS",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ssZ",
        ]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }
        return ISO8601DateFormatter().date(from: trimmed)
    }

    private static func stringValue(_ any: Any?) -> String? {
        guard let any else { return nil }
        if let s = any as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        return nil
    }
}
