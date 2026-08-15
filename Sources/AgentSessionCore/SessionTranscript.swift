import Foundation

/// How to present the Detail stream.
public enum DetailViewMode: String, Sendable, Codable, CaseIterable {
    /// Coalesced user/assistant turns; tools as compact chips (default UI).
    case readable
    /// Every normalized Event from the agent log, including thinking and tool payloads.
    case fullTrace = "full_trace"
}

/// Load and shape a Session’s Detail stream for UI and CLI.
public enum SessionTranscript {
    /// Load raw normalized events for Grok session directories (`updates.jsonl`).
    public static func loadEvents(sessionDirectory: URL) throws -> [SessionEvent] {
        try GrokUpdates.loadEvents(sessionDirectory: sessionDirectory)
    }

    /// Load events using the session’s agent kind (Grok directory vs Claude JSONL file).
    public static func loadEvents(session: SessionInfo) throws -> [SessionEvent] {
        switch session.agent {
        case .grokBuild:
            let dir = URL(fileURLWithPath: session.directoryPath, isDirectory: true)
            return try GrokUpdates.loadEvents(sessionDirectory: dir)
        case .claudeCode:
            let file = URL(fileURLWithPath: session.directoryPath)
            return try ClaudeTranscript.loadEventsExpanded(from: file)
        case .codex:
            let file = URL(fileURLWithPath: session.directoryPath)
            return try CodexTranscript.loadEvents(from: file)
        case .warp:
            return try WarpTranscript.loadEvents(locator: session.directoryPath)
        }
    }

    /// Events shaped for a given view mode.
    public static func events(for session: SessionInfo, mode: DetailViewMode) throws -> [SessionEvent] {
        let raw = try loadEvents(session: session)
        switch mode {
        case .fullTrace:
            return raw
        case .readable:
            return coalesceForReadable(raw)
        }
    }

    /// Merge consecutive text chunks of the same role into single messages.
    /// Tool events stay separate; empty noise is dropped in readable mode.
    public static func coalesceForReadable(_ events: [SessionEvent]) -> [SessionEvent] {
        var result: [SessionEvent] = []
        var buffer: SessionEvent?

        func flush() {
            if let b = buffer {
                let text = b.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !text.isEmpty || b.type == "tool_use" || b.type == "tool_result" {
                    result.append(b)
                }
                buffer = nil
            }
        }

        for event in events {
            switch event.type {
            case "user", "assistant", "thinking":
                if var b = buffer, b.type == event.type, b.role == event.role {
                    let next = event.content ?? ""
                    if !next.isEmpty {
                        b.content = (b.content ?? "") + next
                    }
                    // Keep first id; extend timestamp to latest.
                    b.timestamp = event.timestamp ?? b.timestamp
                    buffer = b
                } else {
                    flush()
                    buffer = event
                }
            case "tool_use", "tool_result":
                flush()
                result.append(event)
            default:
                // Skip noisy system/hook noise in readable mode.
                continue
            }
        }
        flush()
        return result
    }

    /// Human-readable label for an event type.
    public static func displayLabel(for event: SessionEvent) -> String {
        switch event.type {
        case "user": return "USER"
        case "assistant": return "ASSISTANT"
        case "thinking": return "THINKING"
        case "tool_use": return "TOOL"
        case "tool_result": return event.isError ? "TOOL ERROR" : "TOOL RESULT"
        default: return event.type.uppercased()
        }
    }
}
