import XCTest
@testable import AgentSessionCore

final class DiscoveryTests: XCTestCase {
    private var fixtureHome: URL {
        Bundle.module.url(forResource: "grok-home", withExtension: nil, subdirectory: "Fixtures")!
    }

    func testListProjects() throws {
        let catalog = GrokCatalog(dataRoot: fixtureHome)
        let projects = try catalog.listProjects()
        XCTAssertEqual(projects.count, 2)
        let paths = Set(projects.map(\.path))
        XCTAssertEqual(paths, ["/Users/demo/project-a", "/Users/demo/project-b"])
        let byPath = Dictionary(uniqueKeysWithValues: projects.map { ($0.path, $0) })
        XCTAssertEqual(byPath["/Users/demo/project-a"]?.sessionCount, 1)
        XCTAssertEqual(byPath["/Users/demo/project-a"]?.displayName, "project-a")
    }

    func testListSessionsAndTitles() throws {
        let catalog = GrokCatalog(dataRoot: fixtureHome)
        let sessions = try catalog.listSessions()
        XCTAssertEqual(sessions.count, 2)

        let byId = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        XCTAssertEqual(byId["sess-aaa-1111-1111-1111-111111111111"]?.title, "Wire up authentication flow")
        // Empty summary → first user message
        XCTAssertEqual(
            byId["sess-bbb-2222-2222-2222-222222222222"]?.title,
            "Fix the flaky integration test in payments"
        )
    }

    func testListSessionsFilteredByProject() throws {
        let catalog = GrokCatalog(dataRoot: fixtureHome)
        let projectId = "%2FUsers%2Fdemo%2Fproject-a"
        let sessions = try catalog.listSessions(projectId: projectId)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].id, "sess-aaa-1111-1111-1111-111111111111")
    }

    func testShowSession() throws {
        let catalog = GrokCatalog(dataRoot: fixtureHome)
        let session = try catalog.session(id: "sess-aaa-1111-1111-1111-111111111111")
        XCTAssertEqual(session.model, "grok-4.5")
        XCTAssertTrue(session.directoryPath.contains("sess-aaa"))
    }

    func testExportBundle() throws {
        let catalog = GrokCatalog(dataRoot: fixtureHome)
        let session = try catalog.session(id: "sess-aaa-1111-1111-1111-111111111111")
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("asv-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let file = try SessionExporter.exportSession(session: session, to: tmp)
        let data = try Data(contentsOf: file)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(obj["schema_version"] as? Int, 1)
        XCTAssertEqual(obj["agent"] as? String, "grok-build")
        let events = obj["events"] as? [Any]
        XCTAssertEqual(events?.count, 3)
    }

    func testDataRootResolve() {
        let custom = DataRoot.resolve(override: "/tmp/custom-grok", environment: [:])
        XCTAssertEqual(custom.path, "/tmp/custom-grok")

        let fromEnv = DataRoot.resolve(override: nil, environment: ["GROK_HOME": "/tmp/from-env"])
        XCTAssertEqual(fromEnv.path, "/tmp/from-env")
    }
}

final class DeleteSessionTests: XCTestCase {
    private func copyFixture(named name: String) throws -> URL {
        let src = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")!
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("asv-del-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.copyItem(at: src, to: dest)
        return dest
    }

    func testDeleteGrokSessionRemovesDirectoryAndSiblingIntact() throws {
        let home = try copyFixture(named: "grok-home")
        defer { try? FileManager.default.removeItem(at: home) }

        let catalog = GrokCatalog(dataRoot: home)
        let before = try catalog.listSessions()
        XCTAssertEqual(before.count, 2)

        let id = "sess-aaa-1111-1111-1111-111111111111"
        let session = try catalog.session(id: id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: session.directoryPath))

        let result = try catalog.deleteSession(id: id)
        XCTAssertEqual(result.sessionId, id)
        XCTAssertEqual(result.agent, .grokBuild)
        XCTAssertFalse(FileManager.default.fileExists(atPath: session.directoryPath))

        XCTAssertThrowsError(try catalog.session(id: id)) { error in
            XCTAssertEqual(error as? AgentCatalogError, .sessionNotFound(id))
        }
        let after = try catalog.listSessions()
        XCTAssertEqual(after.count, 1)
        XCTAssertEqual(after[0].id, "sess-bbb-2222-2222-2222-222222222222")
    }

    func testDeleteClaudeSessionRemovesJsonl() throws {
        let home = try copyFixture(named: "claude-home")
        defer { try? FileManager.default.removeItem(at: home) }

        let catalog = ClaudeCatalog(dataRoot: home)
        let id = "sess-cc-1111-1111-1111-111111111111"
        let session = try catalog.session(id: id)
        _ = try catalog.deleteSession(id: id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: session.directoryPath))
        XCTAssertEqual(try catalog.listSessions().count, 0)
    }

    func testDeleteCodexSessionRemovesRollout() throws {
        let home = try copyFixture(named: "codex-home")
        defer { try? FileManager.default.removeItem(at: home) }

        let catalog = CodexCatalog(dataRoot: home)
        let id = "019fa3e1-4f4b-75d3-aaec-0f06740b6e9f"
        let session = try catalog.session(id: id)
        _ = try catalog.deleteSession(id: id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: session.directoryPath))
        XCTAssertEqual(try catalog.listSessions().count, 0)
    }

    func testSessionDeleterRefusesPathOutsideDataRoot() throws {
        let home = try copyFixture(named: "grok-home")
        defer { try? FileManager.default.removeItem(at: home) }

        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("asv-outside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }

        let fake = SessionInfo(
            id: "evil",
            agent: .grokBuild,
            title: "evil",
            projectId: "p",
            projectPath: "/tmp",
            createdAt: nil,
            updatedAt: nil,
            messageCount: 0,
            model: nil,
            directoryPath: outside.path,
            rawSummary: nil
        )
        XCTAssertThrowsError(
            try SessionDeleter.delete(session: fake, dataRoot: home, pathKind: .directory)
        ) { error in
            guard case AgentCatalogError.pathOutsideDataRoot = error as? AgentCatalogError else {
                return XCTFail("expected pathOutsideDataRoot, got \(error)")
            }
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    func testIsStrictlyUnder() {
        let parent = URL(fileURLWithPath: "/tmp/root")
        let child = URL(fileURLWithPath: "/tmp/root/a/b")
        let sibling = URL(fileURLWithPath: "/tmp/root-evil")
        XCTAssertTrue(SessionDeleter.isStrictlyUnder(child: child, parent: parent))
        XCTAssertFalse(SessionDeleter.isStrictlyUnder(child: parent, parent: parent))
        XCTAssertFalse(SessionDeleter.isStrictlyUnder(child: sibling, parent: parent))
    }
}

final class SessionTitleTests: XCTestCase {
    func testPreferSummary() {
        let title = SessionTitle.resolve(
            sessionId: "abcdefghijklmnop",
            summary: "  Hello  ",
            firstUserMessage: "ignored"
        )
        XCTAssertEqual(title, "Hello")
    }

    func testFallbackUserThenId() {
        XCTAssertEqual(
            SessionTitle.resolve(sessionId: "abcdefghijklmnop", summary: "  ", firstUserMessage: "Do the thing"),
            "Do the thing"
        )
        XCTAssertEqual(
            SessionTitle.resolve(sessionId: "abcdefghijklmnop", summary: nil, firstUserMessage: nil),
            "abcdefgh…"
        )
    }
}
