import AgentSessionCore
import Foundation

/// Fixture-based smoke checks (no XCTest — works with Command Line Tools only).
@main
struct ASVCheck {
    static func main() {
        var failures = 0

        func expect(_ cond: @autoclosure () -> Bool, _ message: String) {
            if !cond() {
                fputs("FAIL: \(message)\n", stderr)
                failures += 1
            } else {
                print("ok  \(message)")
            }
        }

        // Title rules
        expect(
            SessionTitle.resolve(sessionId: "abcdefghijklmnop", summary: "  Hello  ", firstUserMessage: "x") == "Hello",
            "title prefers summary"
        )
        expect(
            SessionTitle.resolve(sessionId: "abcdefghijklmnop", summary: " ", firstUserMessage: "Do the thing") == "Do the thing",
            "title falls back to user message"
        )
        expect(
            SessionTitle.resolve(sessionId: "abcdefghijklmnop", summary: nil, firstUserMessage: nil) == "abcdefgh…",
            "title falls back to short id"
        )

        // Data root
        expect(
            DataRoot.resolve(override: "/tmp/custom-grok", environment: [:]).path == "/tmp/custom-grok",
            "data root override"
        )
        expect(
            DataRoot.resolve(override: nil, environment: ["GROK_HOME": "/tmp/from-env"]).path == "/tmp/from-env",
            "data root GROK_HOME"
        )

        // Fixture catalog
        let fixtureHome = fixtureGrokHome()
        expect(FileManager.default.fileExists(atPath: fixtureHome.path), "fixture home exists at \(fixtureHome.path)")

        do {
            let catalog = GrokCatalog(dataRoot: fixtureHome)
            let projects = try catalog.listProjects()
            expect(projects.count == 2, "2 projects in fixtures (got \(projects.count))")
            let paths = Set(projects.map(\.path))
            expect(paths == ["/Users/demo/project-a", "/Users/demo/project-b"], "project paths decoded")

            let sessions = try catalog.listSessions()
            expect(sessions.count == 2, "2 sessions in fixtures")
            let byId = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
            expect(
                byId["sess-aaa-1111-1111-1111-111111111111"]?.title == "Wire up authentication flow",
                "summary title"
            )
            expect(
                byId["sess-bbb-2222-2222-2222-222222222222"]?.title
                    == "Fix the flaky integration test in payments",
                "user-message title fallback"
            )

            let filtered = try catalog.listSessions(projectId: "%2FUsers%2Fdemo%2Fproject-a")
            expect(filtered.count == 1, "filter by project id")

            let session = try catalog.session(id: "sess-aaa-1111-1111-1111-111111111111")
            expect(session.model == "grok-4.5", "show model")

            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("asv-check-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: tmp) }
            let file = try SessionExporter.exportSession(session: session, to: tmp)
            let data = try Data(contentsOf: file)
            let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            expect(obj?["schema_version"] as? Int == 1, "export schema_version")
            expect(obj?["agent"] as? String == "grok-build", "export agent")
            expect((obj?["events"] as? [Any])?.count == 3, "export events count")

            let full = try SessionTranscript.events(for: session, mode: .fullTrace)
            expect(full.count == 3, "full trace event count (got \(full.count))")
            let readable = try SessionTranscript.events(for: session, mode: .readable)
            expect(!readable.isEmpty, "readable transcript non-empty")
            expect(readable.contains(where: { $0.type == "user" }), "readable has user turn")
            expect(readable.contains(where: { $0.type == "assistant" }), "readable has assistant turn")

            let allSessions = try catalog.listSessions()
            let loginHits = ConversationSearch.search(sessions: allSessions, query: "Add login")
            expect(loginHits.count == 1, "search Add login → 1 session (got \(loginHits.count))")
            expect(
                loginHits.first?.session.id == "sess-aaa-1111-1111-1111-111111111111",
                "search hit is sess-aaa"
            )
            expect((loginHits.first?.matchCount ?? 0) >= 1, "login matchCount >= 1")

            let flakyHits = ConversationSearch.search(sessions: allSessions, query: "flaky integration")
            expect(flakyHits.count == 1, "search flaky → 1 session")
            expect(
                flakyHits.first?.session.id == "sess-bbb-2222-2222-2222-222222222222",
                "search hit is sess-bbb"
            )

            // Rank: invent higher match count session first via multi-hit phrase present once each —
            // "tool" may appear in tool events; just ensure empty query yields nothing via API contract.
            let emptyHits = ConversationSearch.search(sessions: allSessions, query: "   ")
            expect(emptyHits.isEmpty, "blank query → no hits")
            let miss = ConversationSearch.search(sessions: allSessions, query: "zzznomatch999")
            expect(miss.isEmpty, "miss query → no hits")
        } catch {
            fputs("FAIL: catalog/export threw \(error)\n", stderr)
            failures += 1
        }

        // Claude Code fixture
        let claudeHome = fixtureClaudeHome()
        expect(FileManager.default.fileExists(atPath: claudeHome.path), "claude fixture exists")
        do {
            let store = ClaudeCatalog(dataRoot: claudeHome)
            expect(store.agent == .claudeCode, "claude agent kind")
            let projects = try store.listProjects()
            expect(projects.count == 1, "claude 1 project (got \(projects.count))")
            let sessions = try store.listSessions(projectId: nil)
            expect(sessions.count == 1, "claude 1 session")
            let s = try store.session(id: "sess-cc-1111-1111-1111-111111111111")
            expect(s.title == "Claude fixture hello world", "claude title from ai-title")
            expect(s.agent == .claudeCode, "session agent claude-code")
            expect(s.projectPath == "/Users/demo/proj", "claude cwd from jsonl")
            let events = try store.loadEvents(session: s)
            expect(events.contains(where: { $0.type == "user" }), "claude has user")
            expect(events.contains(where: { $0.type == "assistant" }), "claude has assistant")
            expect(events.contains(where: { $0.type == "tool_use" }), "claude has tool_use")
            expect(events.contains(where: { $0.type == "tool_result" }), "claude has tool_result")
            let hits = ConversationSearch.search(sessions: sessions, query: "Claude integration") {
                try store.loadEvents(session: $0)
            }
            expect(hits.count == 1, "claude search hit")
            let exportURL = try SessionExporter.exportSession(
                session: s,
                to: FileManager.default.temporaryDirectory.appendingPathComponent("asv-cc-\(UUID().uuidString)", isDirectory: true)
            )
            let obj = try JSONSerialization.jsonObject(with: Data(contentsOf: exportURL)) as? [String: Any]
            expect(obj?["agent"] as? String == "claude-code", "export agent claude-code")
        } catch {
            fputs("FAIL: claude catalog threw \(error)\n", stderr)
            failures += 1
        }

        // Codex fixture
        let codexHome = fixtureCodexHome()
        expect(FileManager.default.fileExists(atPath: codexHome.path), "codex fixture exists")
        do {
            let store = CodexCatalog(dataRoot: codexHome)
            expect(store.agent == .codex, "codex agent kind")
            let projects = try store.listProjects()
            expect(projects.count == 1, "codex 1 project (got \(projects.count))")
            let sessions = try store.listSessions(projectId: nil)
            expect(sessions.count == 1, "codex 1 session")
            let sid = "019fa3e1-4f4b-75d3-aaec-0f06740b6e9f"
            let s = try store.session(id: sid)
            expect(s.title == "Codex fixture demo", "codex title from index")
            expect(s.agent == .codex, "session agent codex")
            expect(s.projectPath == "/Users/demo/codex-proj", "codex cwd")
            let events = try store.loadEvents(session: s)
            expect(events.contains(where: { $0.type == "user" }), "codex has user")
            expect(events.contains(where: { $0.type == "assistant" }), "codex has assistant")
            expect(events.contains(where: { $0.type == "tool_use" }), "codex has tool_use")
            expect(events.contains(where: { $0.type == "tool_result" }), "codex has tool_result")
            let hits = ConversationSearch.search(sessions: sessions, query: "rollout parser") {
                try store.loadEvents(session: $0)
            }
            expect(hits.count == 1, "codex search hit")
            let exportURL = try SessionExporter.exportSession(
                session: s,
                to: FileManager.default.temporaryDirectory.appendingPathComponent("asv-cx-\(UUID().uuidString)", isDirectory: true)
            )
            let obj = try JSONSerialization.jsonObject(with: Data(contentsOf: exportURL)) as? [String: Any]
            expect(obj?["agent"] as? String == "codex", "export agent codex")
        } catch {
            fputs("FAIL: codex catalog threw \(error)\n", stderr)
            failures += 1
        }

        if failures > 0 {
            fputs("\n\(failures) failure(s)\n", stderr)
            exit(1)
        }
        print("\nAll checks passed.")
    }

    /// Resolve Fixtures/grok-home relative to the package (works from `swift run`).
    static func fixtureGrokHome() -> URL {
        fixturesRoot().appendingPathComponent("grok-home", isDirectory: true)
    }

    static func fixtureClaudeHome() -> URL {
        fixturesRoot().appendingPathComponent("claude-home", isDirectory: true)
    }

    static func fixtureCodexHome() -> URL {
        fixturesRoot().appendingPathComponent("codex-home", isDirectory: true)
    }

    static func fixturesRoot() -> URL {
        // #filePath = .../Sources/asv-check/main.swift
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let root = sources.deletingLastPathComponent().deletingLastPathComponent()
        return root.appendingPathComponent("Tests/AgentSessionCoreTests/Fixtures", isDirectory: true)
    }
}
