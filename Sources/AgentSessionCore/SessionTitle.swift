import Foundation

public enum SessionTitle {
    /// Prefer non-empty summary → first user message → short session id.
    public static func resolve(
        sessionId: String,
        summary: String?,
        firstUserMessage: String?
    ) -> String {
        if let summary {
            let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        if let firstUserMessage {
            let trimmed = firstUserMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return truncate(trimmed, limit: 80)
            }
        }
        return shortId(sessionId)
    }

    public static func shortId(_ sessionId: String) -> String {
        if sessionId.count <= 12 {
            return sessionId
        }
        let prefix = sessionId.prefix(8)
        return "\(prefix)…"
    }

    public static func truncate(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        let end = text.index(text.startIndex, offsetBy: limit)
        return String(text[..<end]) + "…"
    }
}
