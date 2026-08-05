import Foundation

/// Parse Claude Code `projects/<cwd>/<sessionId>.jsonl` into normalized events + metadata.
enum ClaudeTranscript {
    struct SessionMeta {
        var title: String?
        var firstUserMessage: String?
        var createdAt: Date?
        var updatedAt: Date?
        var messageCount: Int
        var model: String?
        var cwd: String?
    }

    static func loadEvents(from jsonlURL: URL) throws -> [SessionEvent] {
        let data = try Data(contentsOf: jsonlURL)
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        var events: [SessionEvent] = []
        var index = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            index += 1
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
                continue
            }
            if let event = normalizeLine(obj, fallbackId: "cc-\(index)") {
                events.append(event)
            }
        }
        return events
    }

    static func loadMeta(from jsonlURL: URL) -> SessionMeta {
        var meta = SessionMeta(messageCount: 0)
        guard let data = try? Data(contentsOf: jsonlURL),
              let text = String(data: data, encoding: .utf8)
        else { return meta }

        var userAssistant = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
                continue
            }
            let type = obj["type"] as? String
            let ts = parseDate(obj["timestamp"])
            if let ts {
                if meta.createdAt == nil || ts < meta.createdAt! { meta.createdAt = ts }
                if meta.updatedAt == nil || ts > meta.updatedAt! { meta.updatedAt = ts }
            }
            if let cwd = obj["cwd"] as? String, !cwd.isEmpty {
                meta.cwd = cwd
            }
            if type == "ai-title", let t = obj["aiTitle"] as? String, !t.isEmpty {
                meta.title = t
            }
            if type == "user" || type == "assistant" {
                userAssistant += 1
            }
            if type == "user", meta.firstUserMessage == nil {
                if let text = extractUserText(obj) {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty, !trimmed.hasPrefix("<local-command") {
                        meta.firstUserMessage = trimmed
                    }
                }
            }
            if type == "assistant", meta.model == nil {
                if let message = obj["message"] as? [String: Any],
                   let model = message["model"] as? String
                {
                    meta.model = model
                }
            }
        }
        meta.messageCount = userAssistant
        if meta.createdAt == nil || meta.updatedAt == nil {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: jsonlURL.path),
               let mod = attrs[.modificationDate] as? Date
            {
                if meta.createdAt == nil { meta.createdAt = mod }
                if meta.updatedAt == nil { meta.updatedAt = mod }
            }
        }
        return meta
    }

    // MARK: - Normalize

    private static func normalizeLine(_ obj: [String: Any], fallbackId: String) -> SessionEvent? {
        let type = obj["type"] as? String ?? "other"
        let ts = parseDate(obj["timestamp"])
        let eventId = (obj["uuid"] as? String) ?? fallbackId
        let raw = (try? JSONValue.fromAny(obj))?.objectDictionary ?? [:]

        switch type {
        case "user":
            // Tool results often arrive as user messages with tool_result blocks.
            if let blocks = messageContentBlocks(obj) {
                if let toolResult = blocks.first(where: { ($0["type"] as? String) == "tool_result" }) {
                    let text = extractTextFromBlocks([toolResult])
                    let isError = toolResult["is_error"] as? Bool ?? false
                    return SessionEvent(
                        id: eventId,
                        type: "tool_result",
                        timestamp: ts,
                        role: "tool",
                        content: text.isEmpty ? "tool_result" : text,
                        toolCallId: toolResult["tool_use_id"] as? String,
                        isError: isError,
                        raw: raw
                    )
                }
                let text = extractTextFromBlocks(blocks)
                if text.isEmpty { return nil }
                return SessionEvent(
                    id: eventId,
                    type: "user",
                    timestamp: ts,
                    role: "user",
                    content: text,
                    raw: raw
                )
            }
            if let text = extractUserText(obj), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return SessionEvent(
                    id: eventId,
                    type: "user",
                    timestamp: ts,
                    role: "user",
                    content: text,
                    raw: raw
                )
            }
            return nil

        case "assistant":
            let message = obj["message"] as? [String: Any]
            let blocks = messageContentBlocks(obj) ?? []
            var events: [SessionEvent] = []
            // Expand tool_use into separate events; also emit assistant text if any.
            let text = extractTextFromBlocks(blocks)
            if !text.isEmpty {
                events.append(SessionEvent(
                    id: eventId,
                    type: "assistant",
                    timestamp: ts,
                    role: "assistant",
                    content: text,
                    raw: raw
                ))
            }
            for (i, block) in blocks.enumerated() where (block["type"] as? String) == "tool_use" {
                let name = block["name"] as? String
                let input = block["input"]
                var content = name ?? "tool"
                if let input, let s = stringifyJSON(input) {
                    content += "\n" + s
                }
                events.append(SessionEvent(
                    id: "\(eventId)-tool-\(i)",
                    type: "tool_use",
                    timestamp: ts,
                    role: "assistant",
                    content: content,
                    toolName: name,
                    toolCallId: block["id"] as? String,
                    raw: (try? JSONValue.fromAny(block))?.objectDictionary ?? [:]
                ))
            }
            // If only tool_use with no text, events non-empty; if empty, skip.
            // normalizeLine returns one event — for multiple tool uses we need to flatten in loadEvents.
            // Handle multi-event by special path in loadEvents.
            _ = message
            return events.first // multi handled below in loadEventsMulti

        case "ai-title", "queue-operation", "attachment", "file-history-snapshot",
             "mode", "permission-mode", "last-prompt", "system":
            // Full-trace noise: skip (readable would drop them anyway).
            return nil

        default:
            return SessionEvent(
                id: eventId,
                type: type,
                timestamp: ts,
                content: type,
                raw: raw
            )
        }
    }

    /// Load events expanding assistant tool_use arrays into multiple SessionEvents.
    static func loadEventsExpanded(from jsonlURL: URL) throws -> [SessionEvent] {
        let data = try Data(contentsOf: jsonlURL)
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        var events: [SessionEvent] = []
        var index = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            index += 1
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
                continue
            }
            let type = obj["type"] as? String ?? "other"
            let ts = parseDate(obj["timestamp"])
            let eventId = (obj["uuid"] as? String) ?? "cc-\(index)"
            let raw = (try? JSONValue.fromAny(obj))?.objectDictionary ?? [:]

            if type == "assistant" {
                let blocks = messageContentBlocks(obj) ?? []
                let text = extractTextFromBlocks(blocks)
                if !text.isEmpty {
                    events.append(SessionEvent(
                        id: eventId,
                        type: "assistant",
                        timestamp: ts,
                        role: "assistant",
                        content: text,
                        raw: raw
                    ))
                }
                for (i, block) in blocks.enumerated() where (block["type"] as? String) == "tool_use" {
                    let name = block["name"] as? String
                    var content = name ?? "tool"
                    if let input = block["input"], let s = stringifyJSON(input) {
                        content += "\n" + s
                    }
                    events.append(SessionEvent(
                        id: "\(eventId)-tool-\(i)",
                        type: "tool_use",
                        timestamp: ts,
                        role: "assistant",
                        content: content,
                        toolName: name,
                        toolCallId: block["id"] as? String,
                        raw: (try? JSONValue.fromAny(block))?.objectDictionary ?? [:]
                    ))
                }
                continue
            }

            if let event = normalizeLine(obj, fallbackId: "cc-\(index)") {
                events.append(event)
            }
        }
        return events
    }

    private static func messageContentBlocks(_ obj: [String: Any]) -> [[String: Any]]? {
        guard let message = obj["message"] as? [String: Any] else { return nil }
        if let blocks = message["content"] as? [[String: Any]] { return blocks }
        return nil
    }

    private static func extractUserText(_ obj: [String: Any]) -> String? {
        if let message = obj["message"] as? [String: Any] {
            if let s = message["content"] as? String { return s }
            if let blocks = message["content"] as? [[String: Any]] {
                let t = extractTextFromBlocks(blocks)
                return t.isEmpty ? nil : t
            }
        }
        if let s = obj["content"] as? String { return s }
        return nil
    }

    private static func extractTextFromBlocks(_ blocks: [[String: Any]]) -> String {
        var parts: [String] = []
        for block in blocks {
            let t = block["type"] as? String
            if t == "text", let text = block["text"] as? String {
                parts.append(text)
            } else if t == "tool_result" {
                if let content = block["content"] as? String {
                    parts.append(content)
                } else if let content = block["content"] as? [[String: Any]] {
                    parts.append(extractTextFromBlocks(content))
                }
            }
        }
        return parts.joined(separator: "\n")
    }

    private static func parseDate(_ value: Any?) -> Date? {
        guard let s = value as? String else { return nil }
        return ISO8601DateFormatter.fractional.date(from: s)
            ?? ISO8601DateFormatter().date(from: s)
    }

    private static func stringifyJSON(_ value: Any) -> String? {
        if let s = value as? String { return s }
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8)
        else { return String(describing: value) }
        return text
    }
}

private extension JSONValue {
    var objectDictionary: [String: JSONValue]? {
        if case .object(let o) = self { return o }
        return nil
    }

    static func fromAny(_ any: Any) throws -> JSONValue {
        switch any {
        case is NSNull: return .null
        case let b as Bool: return .bool(b)
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return .bool(n.boolValue) }
            return .number(n.doubleValue)
        case let s as String: return .string(s)
        case let a as [Any]: return .array(try a.map { try fromAny($0) })
        case let o as [String: Any]:
            var out: [String: JSONValue] = [:]
            for (k, v) in o { out[k] = try fromAny(v) }
            return .object(out)
        default:
            return .string(String(describing: any))
        }
    }
}
