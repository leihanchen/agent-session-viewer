import ArgumentParser
import AgentSessionCore
import Darwin
import Foundation

@main
struct ASV: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "asv",
        abstract: "Agent Session Viewer — list, export, and delete local coding-agent sessions.",
        discussion: """
        Browse coding-agent sessions on disk (Grok Build, Claude Code, Codex) and export
        portable JSON bundles. By default ASV only reads the data root; the delete
        command permanently removes one session’s files (requires confirmation).

        COMMANDS
          list                  Overview of projects and session counts (default)
          projects              List projects (working-directory groups)
          sessions [project]    List sessions, optionally for one project id
          show <session-id>     Show metadata and full conversation for a session
          export <id>|--all     Write full-trace JSON file(s) into a directory
          delete <session-id>   Permanently remove one session from disk

        GLOBAL OPTIONS (most commands)
          --agent <name>        grok-build (default) | claude-code | codex
          --home <path>         Agent data root override
                                (Grok: ~/.grok; Claude: ~/.claude; Codex: ~/.codex)
          --json                Machine-readable JSON on stdout (list/projects/sessions/show)
          -h, --help            Show help for asv or a subcommand
          --version             Print version

        USAGE EXAMPLES
          asv list
          asv list --agent claude-code
          asv list --agent codex
          asv list --home ~/.grok --json
          asv projects --agent claude-code
          asv show 019f623a-a8d1-7591-beff-c41fc716b171
          asv show <claude-session-id> --agent claude-code
          asv show <codex-session-id> --agent codex
          asv export --all --agent codex --out ./out
          asv delete <session-id> --yes
          asv delete <session-id> --agent claude-code --yes

        GETTING HELP FOR ONE COMMAND
          asv list --help
          asv projects --help
          asv sessions --help
          asv show --help
          asv export --help
          asv delete --help
          asv help <command>
        """,
        version: ASVVersion.current,
        subcommands: [
            ListCommand.self,
            ProjectsCommand.self,
            SessionsCommand.self,
            ShowCommand.self,
            ExportCommand.self,
            DeleteCommand.self,
        ],
        defaultSubcommand: ListCommand.self
    )
}

struct HomeOptions: ParsableArguments {
    @Option(
        name: .long,
        help: ArgumentHelp(
            "Agent to browse.",
            discussion: "grok-build (default), claude-code, or codex."
        )
    )
    var agent: String = AgentKind.grokBuild.rawValue

    @Option(
        name: .long,
        help: ArgumentHelp(
            "Data root directory override.",
            discussion: "Grok: $GROK_HOME|~/.grok. Claude: $CLAUDE_CONFIG_DIR|$CLAUDE_HOME|~/.claude. Codex: $CODEX_HOME|~/.codex."
        )
    )
    var home: String?

    func resolvedAgent() throws -> AgentKind {
        guard let kind = AgentKind(rawValue: agent) else {
            throw ValidationError("Unknown agent '\(agent)'. Use: grok-build, claude-code, codex")
        }
        return kind
    }

    func makeStore() throws -> any AgentSessionStore {
        AgentStoreFactory.make(agent: try resolvedAgent(), homeOverride: home)
    }
}

// MARK: - list

struct ListCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "Overview of projects and session counts.",
        discussion: """
        Prints the resolved data root, total project/session counts, and one
        line per project (display name, session count, path, last updated).

        USAGE
          asv list [--home <path>] [--json]
          asv [--home <path>] [--json]          # list is the default command

        OPTIONS
          --home <path>   Data root ($GROK_HOME or ~/.grok by default)
          --json          Print a JSON object with projects[] instead of text

        EXAMPLES
          asv list
          asv list --home ~/.grok
          asv list --json
        """
    )

    @OptionGroup var homeOptions: HomeOptions
    @Flag(name: .long, help: "Print JSON on stdout.")
    var json = false

    func run() throws {
        let store = try homeOptions.makeStore()
        let projects = try store.listProjects()
        let totalSessions = projects.reduce(0) { $0 + $1.sessionCount }

        if json {
            try printJSON([
                "agent": store.agent.rawValue,
                "data_root": store.dataRoot.path,
                "project_count": projects.count,
                "session_count": totalSessions,
                "projects": projects.map { projectJSON($0) },
            ] as [String: Any])
            return
        }

        print("Agent:     \(store.agent.displayName) (\(store.agent.rawValue))")
        print("Data root: \(store.dataRoot.path)")
        print("Projects: \(projects.count)  Sessions: \(totalSessions)")
        print("")
        for p in projects {
            let updated = p.lastUpdated.map { ISO8601DateFormatter().string(from: $0) } ?? "-"
            print("• \(p.displayName)  (\(p.sessionCount) sessions)  \(p.path)")
            print("  updated: \(updated)")
        }
    }
}

// MARK: - projects

struct ProjectsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "projects",
        abstract: "List projects (working-directory groups).",
        discussion: """
        One project per working-directory folder under <data-root>/sessions/.
        Text output is tab-separated: project-id, session-count, path.

        USAGE
          asv projects [--home <path>] [--json]

        OPTIONS
          --home <path>   Data root ($GROK_HOME or ~/.grok by default)
          --json          Print a JSON array of projects

        EXAMPLES
          asv projects
          asv projects --json
          asv projects --home /backup/grok-home
        """
    )

    @OptionGroup var homeOptions: HomeOptions
    @Flag(name: .long, help: "Print JSON on stdout.")
    var json = false

    func run() throws {
        let store = try homeOptions.makeStore()
        let projects = try store.listProjects()

        if json {
            try printJSON(projects.map { projectJSON($0) })
            return
        }

        print("Agent:     \(store.agent.rawValue)")
        print("Data root: \(store.dataRoot.path)")
        for p in projects {
            print("\(p.id)\t\(p.sessionCount)\t\(p.path)")
        }
    }
}

// MARK: - sessions

struct SessionsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sessions",
        abstract: "List sessions, optionally filtered by project id.",
        discussion: """
        Lists sessions under the data root (or one project). Text output is
        tab-separated: session-id, message-count, updated-at, title.

        The optional project argument is the encoded folder name under
        sessions/ (e.g. %2FUsers%2Fyou%2Fmy-project), as shown by `asv projects`.

        USAGE
          asv sessions [--home <path>] [--json]
          asv sessions <project-id> [--home <path>] [--json]

        ARGUMENTS
          <project-id>    Optional. Encoded project folder name from `asv projects`

        OPTIONS
          --home <path>   Data root ($GROK_HOME or ~/.grok by default)
          --json          Print a JSON array of sessions

        EXAMPLES
          asv sessions
          asv sessions --json
          asv sessions '%2FUsers%2Fyou%2Fmy-project'
        """
    )

    @OptionGroup var homeOptions: HomeOptions
    @Argument(help: "Optional project id (encoded cwd folder name from `asv projects`).")
    var project: String?
    @Flag(name: .long, help: "Print JSON on stdout.")
    var json = false

    func run() throws {
        let store = try homeOptions.makeStore()
        let sessions = try store.listSessions(projectId: project)

        if json {
            try printJSON(sessions.map { sessionJSON($0) })
            return
        }

        print("Agent:     \(store.agent.rawValue)")
        print("Data root: \(store.dataRoot.path)")
        for s in sessions {
            let updated = s.updatedAt.map { ISO8601DateFormatter().string(from: $0) } ?? "-"
            print("\(s.id)\t\(s.messageCount)\t\(updated)\t\(s.title)")
        }
    }
}

// MARK: - show

struct ShowCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Show session metadata and every conversation event.",
        discussion: """
        Looks up a session by id and prints Session info, then the full
        conversation / detail stream (user, assistant, thinking, tools).

        Default text mode is Readable (coalesced turns). Pass --full for the
        complete event trace (every chunk and tool update).

        USAGE
          asv show <session-id> [--home <path>] [--full] [--json]

        ARGUMENTS
          <session-id>    Required. Session directory name / UUID

        OPTIONS
          --home <path>   Data root ($GROK_HOME or ~/.grok by default)
          --full          Full trace (all events); default is readable coalesced
          --json          Print JSON: session + events[]

        EXAMPLES
          asv show 019f623a-a8d1-7591-beff-c41fc716b171
          asv show 019f623a-a8d1-7591-beff-c41fc716b171 --full
          asv show 019f623a-a8d1-7591-beff-c41fc716b171 --json
        """
    )

    @OptionGroup var homeOptions: HomeOptions
    @Argument(help: "Session id (directory name under a project).")
    var sessionId: String
    @Flag(name: .long, help: "Print JSON on stdout (session + events).")
    var json = false
    @Flag(name: .long, help: "Show full event trace instead of readable coalesced messages.")
    var full = false

    func run() throws {
        let store = try homeOptions.makeStore()
        let session = try store.session(id: sessionId)
        let mode: DetailViewMode = full ? .fullTrace : .readable
        let raw = try store.loadEvents(session: session)
        let events = mode == .fullTrace ? raw : SessionTranscript.coalesceForReadable(raw)

        if json {
            var payload = sessionJSON(session)
            payload["view_mode"] = mode.rawValue
            payload["event_count"] = events.count
            payload["events"] = events.map { eventJSON($0) }
            try printJSON(payload)
            return
        }

        print("id:        \(session.id)")
        print("title:     \(session.title)")
        print("agent:     \(session.agent.rawValue)")
        print("project:   \(session.projectPath)")
        print("model:     \(session.model ?? "-")")
        print("messages:  \(session.messageCount)")
        print("created:   \(session.createdAt.map { ISO8601DateFormatter().string(from: $0) } ?? "-")")
        print("updated:   \(session.updatedAt.map { ISO8601DateFormatter().string(from: $0) } ?? "-")")
        print("path:      \(session.directoryPath)")
        print("view:      \(mode == .fullTrace ? "full_trace" : "readable")")
        print("events:    \(events.count)")
        print("")
        print("——— Conversation ———")
        if events.isEmpty {
            print("(no conversation events)")
            return
        }
        for (index, event) in events.enumerated() {
            let label = SessionTranscript.displayLabel(for: event)
            let time = event.timestamp.map { ISO8601DateFormatter().string(from: $0) } ?? ""
            let headerParts = [label, time].filter { !$0.isEmpty }
            print("")
            print("[\(index + 1)] \(headerParts.joined(separator: "  "))")
            if let tool = event.toolName, !tool.isEmpty, event.type == "tool_use" || event.type == "tool_result" {
                print("tool: \(tool)\(event.isError ? "  (error)" : "")")
            }
            let body = event.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if body.isEmpty {
                print("(empty)")
            } else {
                print(body)
            }
        }
    }
}

// MARK: - export

struct ExportCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export",
        abstract: "Export full-trace JSON bundle(s) into a directory.",
        discussion: """
        Writes one normalized JSON file per session (schema_version, agent,
        session info, full event trace). Does not modify the data root.
        Provide either a session id or --all.

        USAGE
          asv export <session-id> [--out <dir>] [--home <path>]
          asv export --all [--out <dir>] [--home <path>]

        ARGUMENTS
          <session-id>    Session to export (omit when using --all)

        OPTIONS
          --all           Export every session under the data root
          --out <dir>     Output directory (default: ./asv-export); created if needed
          --home <path>   Data root ($GROK_HOME or ~/.grok by default)

        EXAMPLES
          asv export 019f623a-a8d1-7591-beff-c41fc716b171
          asv export 019f623a-a8d1-7591-beff-c41fc716b171 --out ~/Desktop/asv-out
          asv export --all --out ./out
          asv export --all --home /backup/grok-home --out ./out
        """
    )

    @OptionGroup var homeOptions: HomeOptions
    @Argument(help: "Session id to export. Omit when using --all.")
    var sessionId: String?
    @Flag(name: .long, help: "Export every session under the data root.")
    var all = false
    @Option(
        name: .long,
        help: ArgumentHelp(
            "Output directory for JSON files.",
            discussion: "Created if it does not exist. Default: ./asv-export"
        )
    )
    var out: String = "./asv-export"

    func run() throws {
        let store = try homeOptions.makeStore()
        let outURL = URL(fileURLWithPath: (out as NSString).expandingTildeInPath, isDirectory: true)

        let sessions: [SessionInfo]
        if all {
            sessions = try store.listSessions(projectId: nil)
        } else if let sessionId {
            sessions = [try store.session(id: sessionId)]
        } else {
            throw ValidationError("Provide a session id or --all. See: asv export --help")
        }

        if sessions.isEmpty {
            print("No sessions to export.", to: &StandardError.stream)
            throw ExitCode(1)
        }

        var written: [URL] = []
        for session in sessions {
            let url = try SessionExporter.exportSession(session: session, to: outURL)
            written.append(url)
            print(url.path)
        }
        print("Exported \(written.count) session(s) → \(outURL.path)", to: &StandardError.stream)
    }
}

// MARK: - delete

struct DeleteCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Permanently delete one session from the local data root.",
        discussion: """
        Looks up a session by id and removes its on-disk artifacts (Grok: session
        directory; Claude/Codex: session jsonl file). This cannot be undone.

        Without --yes, prints session details and requires typing "delete" to confirm.
        Non-interactive use must pass --yes.

        USAGE
          asv delete <session-id> [--agent <name>] [--home <path>] [--yes]

        ARGUMENTS
          <session-id>    Required. Session id (directory name / UUID)

        OPTIONS
          --agent <name>  grok-build (default) | claude-code | codex
          --home <path>   Data root override
          --yes           Skip interactive confirmation (required for scripts / no TTY)

        EXAMPLES
          asv delete 019f623a-a8d1-7591-beff-c41fc716b171 --yes
          asv delete <id> --agent claude-code --yes
          asv delete <id> --agent codex --home ~/.codex --yes
        """
    )

    @OptionGroup var homeOptions: HomeOptions
    @Argument(help: "Session id to delete.")
    var sessionId: String
    @Flag(name: .long, help: "Skip confirmation and delete immediately.")
    var yes = false

    func run() throws {
        let store = try homeOptions.makeStore()
        let session = try store.session(id: sessionId)

        if !yes {
            print("About to permanently delete this session:", to: &StandardError.stream)
            print("  agent: \(session.agent.displayName) (\(session.agent.rawValue))", to: &StandardError.stream)
            print("  id:    \(session.id)", to: &StandardError.stream)
            print("  title: \(session.title)", to: &StandardError.stream)
            print("  path:  \(session.directoryPath)", to: &StandardError.stream)
            print("This cannot be undone.", to: &StandardError.stream)

            guard isatty(STDIN_FILENO) != 0 else {
                print(
                    "Non-interactive terminal: pass --yes to confirm deletion.",
                    to: &StandardError.stream
                )
                throw ExitCode(1)
            }

            print("Type 'delete' to confirm: ", terminator: "", to: &StandardError.stream)
            fflush(stderr)
            guard let line = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
                  line == "delete"
            else {
                print("Aborted.", to: &StandardError.stream)
                throw ExitCode(1)
            }
        }

        let result = try store.deleteSession(id: sessionId)
        print("Deleted \(result.sessionId)")
        print("  agent: \(result.agent.rawValue)")
        print("  path:  \(result.deletedPath)")
    }
}

// MARK: - helpers

private func projectJSON(_ p: Project) -> [String: Any] {
    var dict: [String: Any] = [
        "id": p.id,
        "path": p.path,
        "display_name": p.displayName,
        "session_count": p.sessionCount,
        "directory": p.directoryPath,
    ]
    if let lastUpdated = p.lastUpdated {
        dict["last_updated"] = ISO8601DateFormatter().string(from: lastUpdated)
    }
    return dict
}

private func sessionJSON(_ s: SessionInfo) -> [String: Any] {
    var dict: [String: Any] = [
        "id": s.id,
        "agent": s.agent.rawValue,
        "title": s.title,
        "project_id": s.projectId,
        "project_path": s.projectPath,
        "message_count": s.messageCount,
        "directory": s.directoryPath,
    ]
    if let createdAt = s.createdAt {
        dict["created_at"] = ISO8601DateFormatter().string(from: createdAt)
    }
    if let updatedAt = s.updatedAt {
        dict["updated_at"] = ISO8601DateFormatter().string(from: updatedAt)
    }
    if let model = s.model {
        dict["model"] = model
    }
    return dict
}

private func eventJSON(_ e: SessionEvent) -> [String: Any] {
    var dict: [String: Any] = [
        "id": e.id,
        "type": e.type,
        "is_error": e.isError,
    ]
    if let role = e.role { dict["role"] = role }
    if let content = e.content { dict["content"] = content }
    if let toolName = e.toolName { dict["tool_name"] = toolName }
    if let toolCallId = e.toolCallId { dict["tool_call_id"] = toolCallId }
    if let timestamp = e.timestamp {
        dict["timestamp"] = ISO8601DateFormatter().string(from: timestamp)
    }
    return dict
}

private func printJSON(_ value: Any) throws {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
    if let text = String(data: data, encoding: .utf8) {
        print(text)
    }
}

enum StandardError {
    static var stream = StderrOutputStream()
}

struct StderrOutputStream: TextOutputStream {
    mutating func write(_ string: String) {
        fputs(string, stderr)
    }
}
