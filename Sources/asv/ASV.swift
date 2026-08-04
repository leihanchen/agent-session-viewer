import ArgumentParser
import AgentSessionCore
import Foundation

@main
struct ASV: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "asv",
        abstract: "Agent Session Viewer — list and export local coding-agent sessions (read-only).",
        discussion: """
        Browse Grok Build sessions on disk and export portable JSON bundles.
        Does not modify anything under the data root.

        COMMANDS
          list                  Overview of projects and session counts (default)
          projects              List projects (working-directory groups)
          sessions [project]    List sessions, optionally for one project id
          show <session-id>     Show metadata and on-disk path for a session
          export <id>|--all     Write full-trace JSON file(s) into a directory

        GLOBAL OPTIONS (most commands)
          --home <path>         Data root (default: $GROK_HOME or ~/.grok)
          --json                Machine-readable JSON on stdout (list/projects/sessions/show)
          -h, --help            Show help for asv or a subcommand
          --version             Print version

        USAGE EXAMPLES
          asv
          asv list
          asv list --home ~/.grok --json
          asv projects
          asv projects --json
          asv sessions
          asv sessions '%2FUsers%2Fyou%2Fmy-project'
          asv show 019f623a-a8d1-7591-beff-c41fc716b171
          asv show 019f623a-a8d1-7591-beff-c41fc716b171 --json
          asv export 019f623a-a8d1-7591-beff-c41fc716b171 --out ./out
          asv export --all --out ./out
          asv export --all --home /path/to/grok-home --out ./out

        GETTING HELP FOR ONE COMMAND
          asv list --help
          asv projects --help
          asv sessions --help
          asv show --help
          asv export --help
          asv help <command>
        """,
        version: "0.1.0",
        subcommands: [
            ListCommand.self,
            ProjectsCommand.self,
            SessionsCommand.self,
            ShowCommand.self,
            ExportCommand.self,
        ],
        defaultSubcommand: ListCommand.self
    )
}

struct HomeOptions: ParsableArguments {
    @Option(
        name: .long,
        help: ArgumentHelp(
            "Data root directory.",
            discussion: "Defaults to $GROK_HOME when set, otherwise ~/.grok."
        )
    )
    var home: String?
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
        let catalog = GrokCatalog(homeOverride: homeOptions.home)
        let projects = try catalog.listProjects()
        let totalSessions = projects.reduce(0) { $0 + $1.sessionCount }

        if json {
            try printJSON([
                "data_root": catalog.dataRoot.path,
                "project_count": projects.count,
                "session_count": totalSessions,
                "projects": projects.map { projectJSON($0) },
            ] as [String: Any])
            return
        }

        print("Data root: \(catalog.dataRoot.path)")
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
        let catalog = GrokCatalog(homeOverride: homeOptions.home)
        let projects = try catalog.listProjects()

        if json {
            try printJSON(projects.map { projectJSON($0) })
            return
        }

        print("Data root: \(catalog.dataRoot.path)")
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
        let catalog = GrokCatalog(homeOverride: homeOptions.home)
        let sessions = try catalog.listSessions(projectId: project)

        if json {
            try printJSON(sessions.map { sessionJSON($0) })
            return
        }

        print("Data root: \(catalog.dataRoot.path)")
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
        abstract: "Show metadata and on-disk path for a session id.",
        discussion: """
        Looks up a session by id across all projects and prints title, agent,
        project path, model, message counts, timestamps, and directory path.

        USAGE
          asv show <session-id> [--home <path>] [--json]

        ARGUMENTS
          <session-id>    Required. Session directory name / UUID

        OPTIONS
          --home <path>   Data root ($GROK_HOME or ~/.grok by default)
          --json          Print a JSON object

        EXAMPLES
          asv show 019f623a-a8d1-7591-beff-c41fc716b171
          asv show 019f623a-a8d1-7591-beff-c41fc716b171 --json
        """
    )

    @OptionGroup var homeOptions: HomeOptions
    @Argument(help: "Session id (directory name under a project).")
    var sessionId: String
    @Flag(name: .long, help: "Print JSON on stdout.")
    var json = false

    func run() throws {
        let catalog = GrokCatalog(homeOverride: homeOptions.home)
        let session = try catalog.session(id: sessionId)

        if json {
            try printJSON(sessionJSON(session))
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
        let catalog = GrokCatalog(homeOverride: homeOptions.home)
        let outURL = URL(fileURLWithPath: (out as NSString).expandingTildeInPath, isDirectory: true)

        let sessions: [SessionInfo]
        if all {
            sessions = try catalog.listSessions()
        } else if let sessionId {
            sessions = [try catalog.session(id: sessionId)]
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
