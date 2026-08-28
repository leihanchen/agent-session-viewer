import Foundation
import CoreFoundation

/// Parse Codex `sessions/**/rollout-*.jsonl` into normalized events + session meta.
enum CodexTranscript {
    struct SessionMeta {
        var sessionId: String?
        var cwd: String?
        var title: String?
        var firstUserMessage: String?
        var createdAt: Date?
        var updatedAt: Date?
        var messageCount: Int
        var model: String?
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
            events.append(contentsOf: normalizeRecord(obj, fallbackId: "codex-\(index)"))
        }
        return events
    }

    static func loadMeta(from jsonlURL: URL, indexTitle: String? = nil) -> SessionMeta {
        var meta = SessionMeta(messageCount: 0)
        meta.title = indexTitle
        if let sid = CodexPaths.sessionId(fromRolloutFilename: jsonlURL.lastPathComponent) {
            meta.sessionId = sid
        }
        guard let data = try? Data(contentsOf: jsonlURL),
              let text = String(data: data, encoding: .utf8)
        else {
            applyFileDates(jsonlURL, to: &meta)
            return meta
        }

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
            let payload = obj["payload"] as? [String: Any] ?? [:]

            if type == "session_meta" {
                if let id = payload["session_id"] as? String ?? payload["id"] as? String {
                    meta.sessionId = id
                }
                if let cwd = payload["cwd"] as? String, !cwd.isEmpty {
                    meta.cwd = cwd
                }
            }
            if type == "turn_context" {
                if let cwd = payload["cwd"] as? String, !cwd.isEmpty, meta.cwd == nil {
                    meta.cwd = cwd
                }
                if let model = payload["model"] as? String {
                    meta.model = model
                }
            }
            if type == "response_item" {
                let pType = payload["type"] as? String
                if pType == "message" {
                    let role = payload["role"] as? String
                    if role == "user" || role == "assistant" {
                        userAssistant += 1
                    }
                    if role == "user", meta.firstUserMessage == nil {
                        let text = extractMessageText(payload, prefer: "input_text")
                        if let text, !CodexPaths.isNoiseUserText(text) {
                            meta.firstUserMessage = text
                        }
                    }
                }
            }
        }
        meta.messageCount = userAssistant
        applyFileDates(jsonlURL, to: &meta)
        return meta
    }

    // MARK: - Normalize

    private static func normalizeRecord(_ obj: [String: Any], fallbackId: String) -> [SessionEvent] {
        let type = obj["type"] as? String ?? "other"
        let ts = parseDate(obj["timestamp"])
        let payload = obj["payload"] as? [String: Any] ?? [:]

        switch type {
        case "response_item":
            return normalizeResponseItem(payload, timestamp: ts, fallbackId: fallbackId)
        case "session_meta", "event_msg", "turn_context", "world_state":
            return []
        default:
            return []
        }
    }

    private static func normalizeResponseItem(
        _ payload: [String: Any],
        timestamp: Date?,
        fallbackId: String
    ) -> [SessionEvent] {
        let pType = payload["type"] as? String ?? "other"
        let id = (payload["id"] as? String) ?? (payload["call_id"] as? String) ?? fallbackId
        let raw = (try? JSONValue.fromAnyDict(payload)) ?? [:]

        switch pType {
        case "message":
            let role = payload["role"] as? String ?? "user"
            if role == "developer" { return [] }
            if role == "user" {
                let text = extractMessageText(payload, prefer: "input_text") ?? ""
                if text.isEmpty || CodexPaths.isNoiseUserText(text) { return [] }
                return [SessionEvent(
                    id: id,
                    type: "user",
                    timestamp: timestamp,
                    role: "user",
                    content: text,
                    raw: raw
                )]
            }
            if role == "assistant" {
                let text = extractMessageText(payload, prefer: "output_text") ?? ""
                if text.isEmpty { return [] }
                return [SessionEvent(
                    id: id,
                    type: "assistant",
                    timestamp: timestamp,
                    role: "assistant",
                    content: text,
                    raw: raw
                )]
            }
            return []

        case "function_call", "custom_tool_call", "web_search_call":
            let name = payload["name"] as? String
                ?? (pType == "web_search_call" ? "web_search" : "tool")
            var content = name
            if let args = payload["arguments"] as? String {
                content += "\n" + args
            } else if let input = payload["input"] as? String {
                content += "\n" + input
            } else if let input = payload["input"], let s = stringifyJSON(input) {
                content += "\n" + s
            }
            return [SessionEvent(
                id: id,
                type: "tool_use",
                timestamp: timestamp,
                role: "assistant",
                content: content,
                toolName: name,
                toolCallId: payload["call_id"] as? String ?? payload["id"] as? String,
                raw: raw
            )]

        case "function_call_output", "custom_tool_call_output":
            let text = extractToolOutput(payload)
            let status = payload["status"] as? String
            let isError = status == "failed" || status == "error"
            return [SessionEvent(
                id: id,
                type: "tool_result",
                timestamp: timestamp,
                role: "tool",
                content: text.isEmpty ? "tool_result" : text,
                toolName: payload["name"] as? String,
                toolCallId: payload["call_id"] as? String,
                isError: isError,
                raw: raw
            )]

        case "reasoning":
            // Usually encrypted; skip unless summary text exists.
            if let summary = payload["summary"] as? [[String: Any]] {
                let text = summary.compactMap { $0["text"] as? String }.joined(separator: "\n")
                if !text.isEmpty {
                    return [SessionEvent(
                        id: id,
                        type: "thinking",
                        timestamp: timestamp,
                        role: "assistant",
                        content: text,
                        raw: raw
                    )]
                }
            }
            return []

        default:
            return []
        }
    }

    private static func extractMessageText(_ payload: [String: Any], prefer preferred: String) -> String? {
        guard let content = payload["content"] as? [[String: Any]] else {
            return payload["content"] as? String
        }
        var preferredParts: [String] = []
        var otherText: [String] = []
        for block in content {
            let t = block["type"] as? String
            let text = block["text"] as? String
            guard let text, !text.isEmpty else { continue }
            if t == preferred {
                preferredParts.append(text)
            } else if t == "input_text" || t == "output_text" || t == "text" {
                otherText.append(text)
            }
        }
        let parts = preferredParts.isEmpty ? otherText : preferredParts
        let joined = parts.joined(separator: "\n")
        return joined.isEmpty ? nil : joined
    }

    private static func extractToolOutput(_ payload: [String: Any]) -> String {
        if let s = payload["output"] as? String { return s }
        if let arr = payload["output"] as? [[String: Any]] {
            return arr.compactMap { $0["text"] as? String }.joined(separator: "\n")
        }
        if let s = stringifyJSON(payload["output"] as Any) { return s }
        return ""
    }

    private static func applyFileDates(_ url: URL, to meta: inout SessionMeta) {
        if meta.createdAt != nil, meta.updatedAt != nil { return }
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let mod = attrs[.modificationDate] as? Date
        {
            if meta.createdAt == nil { meta.createdAt = mod }
            if meta.updatedAt == nil { meta.updatedAt = mod }
        }
    }

    private static func parseDate(_ value: Any?) -> Date? {
        guard let s = value as? String else { return nil }
        return ISO8601DateFormatter.fractional.date(from: s)
            ?? ISO8601DateFormatter().date(from: s)
    }

    private static func stringifyJSON(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let s = value as? String { return s }
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8)
        else { return String(describing: value) }
        return text
    }
}

private extension JSONValue {
    static func fromAnyDict(_ dict: [String: Any]) throws -> [String: JSONValue] {
        var out: [String: JSONValue] = [:]
        for (k, v) in dict {
            out[k] = try fromAny(v)
        }
        return out
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
