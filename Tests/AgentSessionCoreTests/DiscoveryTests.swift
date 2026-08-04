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
