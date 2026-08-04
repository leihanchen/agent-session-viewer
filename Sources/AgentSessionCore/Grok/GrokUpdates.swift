import Foundation

/// Grok Build `updates.jsonl` parser (internal to Core; use `SessionTranscript` from app/CLI).
enum GrokUpdates {
    /// Scan `updates.jsonl` for the first user-visible message text.
    static func firstUserMessage(in url: URL) -> String? {
        guard FileManager.default.fileExists(atPath: url.path),
              let handle = try? FileHandle(forReadingFrom: url)
        else {
            return nil
        }
        defer { try? handle.close() }

        // Read up to ~1MB for title fallback — enough for early turns.
        let data = handle.readData(ofLength: 1_048_576)
        guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else {
            return nil
        }

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let params = obj["params"] as? [String: Any],
                  let update = params["update"] as? [String: Any],
                  let kind = update["sessionUpdate"] as? String,
                  kind == "user_message_chunk"
            else {
                continue
            }
            if let content = update["content"] as? [String: Any],
               let t = content["text"] as? String,
               !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                return t
            }
        }
        return nil
    }

    /// Load normalized events from `updates.jsonl` (full file).
    static func loadEvents(sessionDirectory: URL) throws -> [SessionEvent] {
        let url = sessionDirectory.appendingPathComponent("updates.jsonl")
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            return []
        }

        var events: [SessionEvent] = []
        var index = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            index += 1
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
                continue
            }
            if let event = normalizeLine(obj, fallbackId: "evt-\(index)") {
                events.append(event)
            }
        }
        return events
    }

    private static func normalizeLine(_ obj: [String: Any], fallbackId: String) -> SessionEvent? {
        let params = obj["params"] as? [String: Any] ?? [:]
        let update = params["update"] as? [String: Any] ?? [:]
        let sessionUpdate = update["sessionUpdate"] as? String

        let ts: Date?
        if let t = obj["timestamp"] as? Double {
            // Grok timestamps: large values may be ms; normal unix seconds otherwise.
            if t > 1_000_000_000_000 {
                ts = Date(timeIntervalSince1970: t / 1000.0)
            } else if t > 1_000_000_000 {
                ts = Date(timeIntervalSince1970: t)
            } else {
                ts = Date(timeIntervalSince1970: t)
            }
        } else {
            ts = nil
        }

        let meta = params["_meta"] as? [String: Any]
        let eventId = (meta?["eventId"] as? String) ?? fallbackId

        let raw = (try? JSONValue.fromJSONObject(obj))?.objectValue ?? [:]

        guard let sessionUpdate else {
            return SessionEvent(
                id: eventId,
                type: "other",
                timestamp: ts,
                content: nil,
                raw: raw
            )
        }

        switch sessionUpdate {
        case "user_message_chunk":
            let text = textContent(update["content"])
            guard let text, !text.isEmpty else { return nil }
            return SessionEvent(
                id: eventId,
                type: "user",
                timestamp: ts,
                role: "user",
                content: text,
                raw: raw
            )
        case "agent_message_chunk":
            let text = textContent(update["content"])
            guard let text, !text.isEmpty else { return nil }
            return SessionEvent(
                id: eventId,
                type: "assistant",
                timestamp: ts,
                role: "assistant",
                content: text,
                raw: raw
            )
        case "agent_thought_chunk":
            let text = textContent(update["content"])
            guard let text, !text.isEmpty else { return nil }
            return SessionEvent(
                id: eventId,
                type: "thinking",
                timestamp: ts,
                role: "assistant",
                content: text,
                raw: raw
            )
        case "tool_call":
            let name = toolName(from: update)
            let inputSummary = stringifyJSON(update["rawInput"])
            let contentParts = [name, inputSummary].compactMap { $0 }.filter { !$0.isEmpty }
            return SessionEvent(
                id: eventId,
                type: "tool_use",
                timestamp: ts,
                role: "assistant",
                content: contentParts.joined(separator: "\n"),
                toolName: name,
                toolCallId: update["toolCallId"] as? String,
                raw: raw
            )
        case "tool_call_update":
            let name = toolName(from: update)
            let status = update["status"] as? String
            let isError = status == "failed" || status == "error"
            let body = toolResultBody(from: update)
            var lines: [String] = []
            if let name, !name.isEmpty { lines.append(name) }
            if let status, !status.isEmpty { lines.append("status: \(status)") }
            if let body, !body.isEmpty { lines.append(body) }
            return SessionEvent(
                id: eventId,
                type: "tool_result",
                timestamp: ts,
                role: "tool",
                content: lines.isEmpty ? name : lines.joined(separator: "\n"),
                toolName: name,
                toolCallId: update["toolCallId"] as? String,
                isError: isError,
                raw: raw
            )
        default:
            // Keep other update kinds for full-trace completeness.
            return SessionEvent(
                id: eventId,
                type: sessionUpdate,
                timestamp: ts,
                content: sessionUpdate,
                raw: raw
            )
        }
    }

    private static func toolName(from update: [String: Any]) -> String? {
        if let title = update["title"] as? String, !title.isEmpty {
            return title
        }
        if let meta = update["_meta"] as? [String: Any],
           let tool = meta["x.ai/tool"] as? [String: Any],
           let name = tool["name"] as? String
        {
            return name
        }
        return nil
    }

    private static func textContent(_ value: Any?) -> String? {
        if let content = value as? [String: Any], let t = content["text"] as? String {
            return t
        }
        if let s = value as? String {
            return s
        }
        return nil
    }

    /// Extract printable tool result body from Grok tool_call_update shapes.
    private static func toolResultBody(from update: [String: Any]) -> String? {
        if let content = update["content"] as? [[String: Any]] {
            var parts: [String] = []
            for item in content {
                if let inner = item["content"] as? [String: Any], let t = inner["text"] as? String {
                    parts.append(t)
                } else if let t = item["text"] as? String {
                    parts.append(t)
                } else if let t = textContent(item["content"]) {
                    parts.append(t)
                }
            }
            if !parts.isEmpty {
                return parts.joined(separator: "\n")
            }
        }
        if let t = textContent(update["content"]) {
            return t
        }
        if let out = update["rawOutput"] {
            return stringifyJSON(out)
        }
        return nil
    }

    private static func stringifyJSON(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let s = value as? String { return s }
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8)
        else {
            return String(describing: value)
        }
        return text
    }
}

private extension JSONValue {
    var objectValue: [String: JSONValue]? {
        if case .object(let o) = self { return o }
        return nil
    }

    static func fromJSONObject(_ any: Any) throws -> JSONValue {
        switch any {
        case is NSNull:
            return .null
        case let b as Bool:
            return .bool(b)
        case let n as NSNumber:
            // Bool is NSNumber in ObjC bridge — handled above if cast order ok; use objCType if needed.
            if CFGetTypeID(n) == CFBooleanGetTypeID() {
                return .bool(n.boolValue)
            }
            return .number(n.doubleValue)
        case let s as String:
            return .string(s)
        case let a as [Any]:
            return .array(try a.map { try fromJSONObject($0) })
        case let o as [String: Any]:
            var out: [String: JSONValue] = [:]
            for (k, v) in o {
                out[k] = try fromJSONObject(v)
            }
            return .object(out)
        default:
            return .string(String(describing: any))
        }
    }
}
