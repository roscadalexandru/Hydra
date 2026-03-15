import XCTest
import GRDB
@testable import hydra

final class ChatSessionTests: XCTestCase {

    private func makeWorkspaceAndDB() throws -> (AppDatabase, Workspace) {
        let db = try TestDatabase.make()
        var workspace = Workspace(name: "Test")
        try db.dbWriter.write { dbConn in
            try workspace.insert(dbConn)
        }
        return (db, workspace)
    }

    func testCreateChatSession() throws {
        let (db, workspace) = try makeWorkspaceAndDB()
        try db.dbWriter.write { dbConn in
            var session = ChatSession(workspaceId: workspace.id!)
            try session.insert(dbConn)

            XCTAssertNotNil(session.id)
            XCTAssertEqual(session.workspaceId, workspace.id)
            XCTAssertEqual(session.status, .active)
            XCTAssertEqual(session.title, "New Chat")
        }
    }

    func testChatSessionDefaults() throws {
        let session = ChatSession(workspaceId: 1)
        XCTAssertNil(session.id)
        XCTAssertEqual(session.status, .active)
        XCTAssertEqual(session.title, "New Chat")
        XCTAssertNil(session.sdkSessionId)
        XCTAssertNil(session.issueId)
        XCTAssertNil(session.totalCostUsd)
        XCTAssertNil(session.totalDurationMs)
    }

    func testUpdateChatSessionStatus() throws {
        let (db, workspace) = try makeWorkspaceAndDB()
        try db.dbWriter.write { dbConn in
            var session = ChatSession(workspaceId: workspace.id!)
            try session.insert(dbConn)

            session.status = .completed
            session.totalCostUsd = 0.05
            session.totalDurationMs = 1500
            try session.update(dbConn)

            let fetched = try ChatSession.fetchOne(dbConn, key: session.id)
            XCTAssertEqual(fetched?.status, .completed)
            XCTAssertEqual(fetched?.totalCostUsd, 0.05)
            XCTAssertEqual(fetched?.totalDurationMs, 1500)
        }
    }

    func testUpdateSdkSessionId() throws {
        let (db, workspace) = try makeWorkspaceAndDB()
        try db.dbWriter.write { dbConn in
            var session = ChatSession(workspaceId: workspace.id!)
            try session.insert(dbConn)

            session.sdkSessionId = "sdk-abc-123"
            try session.update(dbConn)

            let fetched = try ChatSession.fetchOne(dbConn, key: session.id)
            XCTAssertEqual(fetched?.sdkSessionId, "sdk-abc-123")
        }
    }

    func testDeleteChatSession() throws {
        let (db, workspace) = try makeWorkspaceAndDB()
        try db.dbWriter.write { dbConn in
            var session = ChatSession(workspaceId: workspace.id!)
            try session.insert(dbConn)
            let id = session.id

            _ = try session.delete(dbConn)

            let fetched = try ChatSession.fetchOne(dbConn, key: id)
            XCTAssertNil(fetched)
        }
    }

    func testCascadeDeleteWithWorkspace() throws {
        let (db, workspace) = try makeWorkspaceAndDB()
        try db.dbWriter.write { dbConn in
            var session = ChatSession(workspaceId: workspace.id!)
            try session.insert(dbConn)
            let sessionId = session.id

            _ = try Workspace.deleteAll(dbConn)

            let fetched = try ChatSession.fetchOne(dbConn, key: sessionId)
            XCTAssertNil(fetched)
        }
    }

    func testIssueSetNullOnDelete() throws {
        let (db, workspace) = try makeWorkspaceAndDB()
        try db.dbWriter.write { dbConn in
            var issue = hydra.Issue(workspaceId: workspace.id!, title: "Test Issue")
            try issue.insert(dbConn)

            var session = ChatSession(workspaceId: workspace.id!, issueId: issue.id)
            try session.insert(dbConn)

            _ = try hydra.Issue.deleteAll(dbConn)

            let fetched = try ChatSession.fetchOne(dbConn, key: session.id)
            XCTAssertNotNil(fetched)
            XCTAssertNil(fetched?.issueId)
        }
    }

    // MARK: - Project Scoping

    func testCreateSessionWithProjectId() throws {
        let (db, workspace) = try makeWorkspaceAndDB()
        try db.dbWriter.write { dbConn in
            var project = Project(workspaceId: workspace.id!, name: "MyApp", path: "/Users/dev/myapp")
            try project.insert(dbConn)

            var session = ChatSession(workspaceId: workspace.id!, projectId: project.id)
            try session.insert(dbConn)

            let fetched = try ChatSession.fetchOne(dbConn, key: session.id)
            XCTAssertEqual(fetched?.projectId, project.id)
        }
    }

    func testCreateSessionWithoutProjectId() throws {
        let (db, workspace) = try makeWorkspaceAndDB()
        try db.dbWriter.write { dbConn in
            var session = ChatSession(workspaceId: workspace.id!)
            try session.insert(dbConn)

            let fetched = try ChatSession.fetchOne(dbConn, key: session.id)
            XCTAssertNil(fetched?.projectId)
        }
    }

    func testProjectSetNullOnDelete() throws {
        let (db, workspace) = try makeWorkspaceAndDB()
        try db.dbWriter.write { dbConn in
            var project = Project(workspaceId: workspace.id!, name: "MyApp", path: "/tmp/myapp")
            try project.insert(dbConn)

            var session = ChatSession(workspaceId: workspace.id!, projectId: project.id)
            try session.insert(dbConn)

            _ = try Project.deleteAll(dbConn)

            let fetched = try ChatSession.fetchOne(dbConn, key: session.id)
            XCTAssertNotNil(fetched)
            XCTAssertNil(fetched?.projectId)
        }
    }

    // MARK: - Session Listing

    func testFetchSessionsForWorkspaceOrderedByUpdatedAt() throws {
        let (db, workspace) = try makeWorkspaceAndDB()
        try db.dbWriter.write { dbConn in
            let baseDate = Date(timeIntervalSince1970: 1000)

            var session1 = ChatSession(workspaceId: workspace.id!, title: "Old Chat", updatedAt: baseDate)
            try session1.insert(dbConn)

            var session2 = ChatSession(workspaceId: workspace.id!, title: "Recent Chat", updatedAt: baseDate.addingTimeInterval(100))
            try session2.insert(dbConn)

            var session3 = ChatSession(workspaceId: workspace.id!, title: "Newest Chat", updatedAt: baseDate.addingTimeInterval(200))
            try session3.insert(dbConn)

            let sessions = try ChatSession.fetchAllForWorkspace(dbConn, workspaceId: workspace.id!)
            XCTAssertEqual(sessions.count, 3)
            // Most recent first
            XCTAssertEqual(sessions[0].title, "Newest Chat")
            XCTAssertEqual(sessions[1].title, "Recent Chat")
            XCTAssertEqual(sessions[2].title, "Old Chat")
        }
    }

    func testFetchSessionsDoesNotReturnOtherWorkspaces() throws {
        let db = try TestDatabase.make()
        try db.dbWriter.write { dbConn in
            var ws1 = Workspace(name: "WS1")
            try ws1.insert(dbConn)
            var ws2 = Workspace(name: "WS2")
            try ws2.insert(dbConn)

            var s1 = ChatSession(workspaceId: ws1.id!, title: "WS1 Chat")
            try s1.insert(dbConn)
            var s2 = ChatSession(workspaceId: ws2.id!, title: "WS2 Chat")
            try s2.insert(dbConn)

            let sessions = try ChatSession.fetchAllForWorkspace(dbConn, workspaceId: ws1.id!)
            XCTAssertEqual(sessions.count, 1)
            XCTAssertEqual(sessions[0].title, "WS1 Chat")
        }
    }

    // MARK: - Title Generation

    func testGenerateTitleFromFirstMessage() throws {
        let shortMessage = "How do I set up CI/CD?"
        XCTAssertEqual(ChatSession.generateTitle(from: shortMessage), "How do I set up CI/CD?")
    }

    func testGenerateTitleTruncatesLongMessage() throws {
        let longMessage = String(repeating: "a", count: 100)
        let title = ChatSession.generateTitle(from: longMessage)
        XCTAssertTrue(title.count <= 53) // 50 chars + "..."
        XCTAssertTrue(title.hasSuffix("..."))
    }

    func testGenerateTitleTrimsWhitespace() throws {
        let message = "  Hello world  "
        XCTAssertEqual(ChatSession.generateTitle(from: message), "Hello world")
    }
}
