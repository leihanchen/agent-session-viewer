import AgentSessionCore
import Foundation
import Glibc

/// Linux companion UI. It intentionally stays dependency-free so the same
/// binary works on headless servers and desktop distributions alike.
@main
struct AgentSessionViewerLinux {
    static func main() {
        do {
            let args = Array(CommandLine.arguments.dropFirst())
            if args.contains("--help") || args.contains("-h") {
                print("AgentSessionViewer (Linux terminal UI)")
                print("Usage: AgentSessionViewer [--agent <id>] [--home <path>] [--full] [session-id]")
                print("Agents: grok-build (default), claude-code, codex, warp")
                return
            }
            let agent: AgentKind
            if let rawAgent = optionValue("--agent", in: args) {
                guard let parsed = AgentKind(rawValue: rawAgent) else {
                    throw ViewerError.invalid("unknown agent '\(rawAgent)'; use grok-build, claude-code, codex, or warp")
                }
                agent = parsed
            } else {
                agent = .grokBuild
            }
            let store = AgentStoreFactory.make(agent: agent, homeOverride: optionValue("--home", in: args))
            let sessions = try store.listSessions()
            print("Agent: \(agent.displayName) (\(agent.rawValue))")
            print("Data root: \(store.dataRoot.path)")
            print("Projects: \(try store.listProjects().count)  Sessions: \(sessions.count)")
            print("")

            if let id = positionalID(in: args) {
                guard let session = sessions.first(where: { $0.id == id }) else {
                    throw ViewerError.invalid("session not found: \(id)")
                }
                let events = try store.loadEvents(session: session)
                print("\(session.title) [\(session.id)]")
                print("Project: \(session.projectPath)")
                for event in events where shouldDisplay(event, full: args.contains("--full")) {
                    let role = event.role ?? event.type
                    print("[\(role)] \(event.content)")
                }
                return
            }

            for session in sessions {
                print("\(session.id)\t\(session.title)\t\(session.projectPath)")
            }
        } catch {
            fputs("AgentSessionViewer: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func optionValue(_ name: String, in args: [String]) -> String? {
        guard let index = args.firstIndex(of: name), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }

    private static func positionalID(in args: [String]) -> String? {
        let options: Set<String> = ["--agent", "--home"]
        var skip = false
        for arg in args {
            if skip { skip = false; continue }
            if options.contains(arg) { skip = true; continue }
            if !arg.hasPrefix("-") { return arg }
        }
        return nil
    }

    private static func shouldDisplay(_ event: SessionEvent, full: Bool) -> Bool {
        full || event.role == "user" || event.role == "assistant" || event.role == "thinking"
    }
}

private enum ViewerError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        if case .invalid(let message) = self { return message }
        return nil
    }
}
