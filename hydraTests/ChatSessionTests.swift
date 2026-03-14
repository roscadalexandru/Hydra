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
}
