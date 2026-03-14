import XCTest
import GRDB
@testable import hydra

@MainActor
final class ChatSessionListViewModelTests: XCTestCase {

    // MARK: - Loading Sessions

    func testLoadSessionsFetchesForWorkspace() async throws {
        let (vm, db, workspace) = try await makeViewModel()

        try await db.dbWriter.write { dbConn in
            var s1 = ChatSession(workspaceId: workspace.id!, title: "Chat 1")
            try s1.insert(dbConn)
            var s2 = ChatSession(workspaceId: workspace.id!, title: "Chat 2")
            try s2.insert(dbConn)
        }

        try await vm.loadSessions()

        XCTAssertEqual(vm.sessions.count, 2)
    }

    func testLoadSessionsOrderedByMostRecent() async throws {
        let (vm, db, workspace) = try await makeViewModel()
        let base = Date(timeIntervalSince1970: 1000)

        try await db.dbWriter.write { dbConn in
            var s1 = ChatSession(workspaceId: workspace.id!, title: "Old", updatedAt: base)
            try s1.insert(dbConn)
            var s2 = ChatSession(workspaceId: workspace.id!, title: "New", updatedAt: base.addingTimeInterval(100))
            try s2.insert(dbConn)
        }

        try await vm.loadSessions()

        XCTAssertEqual(vm.sessions[0].title, "New")
        XCTAssertEqual(vm.sessions[1].title, "Old")
    }

    // MARK: - Create Session

    func testCreateNewSession() async throws {
        let (vm, db, workspace) = try await makeViewModel()

        let session = try await vm.createSession()

        XCTAssertNotNil(session.id)
        XCTAssertEqual(session.workspaceId, workspace.id)
        XCTAssertEqual(session.title, "New Chat")
        XCTAssertEqual(session.status, .active)

        // Should be in the sessions list
        XCTAssertEqual(vm.sessions.count, 1)
        XCTAssertEqual(vm.sessions[0].id, session.id)

        // Verify persisted
        try await db.dbWriter.read { dbConn in
            let count = try ChatSession.fetchCount(dbConn)
            XCTAssertEqual(count, 1)
        }
    }

    func testCreateSessionWithProjectId() async throws {
        let (vm, db, workspace) = try await makeViewModel()

        var project = Project(workspaceId: workspace.id!, name: "MyApp", path: "/tmp/myapp")
        try await db.dbWriter.write { dbConn in
            try project.insert(dbConn)
        }

        let session = try await vm.createSession(projectId: project.id)

        XCTAssertEqual(session.projectId, project.id)
    }

    // MARK: - Delete Session

    func testDeleteSession() async throws {
        let (vm, db, workspace) = try await makeViewModel()

        try await db.dbWriter.write { dbConn in
            var session = ChatSession(workspaceId: workspace.id!, title: "To Delete")
            try session.insert(dbConn)
        }

        try await vm.loadSessions()
        XCTAssertEqual(vm.sessions.count, 1)

        let sessionToDelete = vm.sessions[0]
        try await vm.deleteSession(sessionToDelete)

        XCTAssertEqual(vm.sessions.count, 0)

        // Verify deleted from DB
        try await db.dbWriter.read { dbConn in
            let count = try ChatSession.fetchCount(dbConn)
            XCTAssertEqual(count, 0)
        }
    }

    // MARK: - Select Session

    func testSelectSessionUpdatesSelectedId() async throws {
        let (vm, db, workspace) = try await makeViewModel()

        try await db.dbWriter.write { dbConn in
            var s1 = ChatSession(workspaceId: workspace.id!, title: "Chat 1")
            try s1.insert(dbConn)
            var s2 = ChatSession(workspaceId: workspace.id!, title: "Chat 2")
            try s2.insert(dbConn)
        }

        try await vm.loadSessions()
        let session = vm.sessions[0]

        vm.selectSession(session)

        XCTAssertEqual(vm.selectedSessionId, session.id)
    }

    func testSelectSessionNilClearsSelection() async throws {
        let (vm, db, workspace) = try await makeViewModel()

        try await db.dbWriter.write { dbConn in
            var s = ChatSession(workspaceId: workspace.id!)
            try s.insert(dbConn)
        }

        try await vm.loadSessions()
        vm.selectSession(vm.sessions[0])
        XCTAssertNotNil(vm.selectedSessionId)

        vm.selectSession(nil)
        XCTAssertNil(vm.selectedSessionId)
    }

    // MARK: - Title Update

    func testUpdateSessionTitle() async throws {
        let (vm, db, workspace) = try await makeViewModel()

        try await db.dbWriter.write { dbConn in
            var s = ChatSession(workspaceId: workspace.id!, title: "New Chat")
            try s.insert(dbConn)
        }

        try await vm.loadSessions()
        let session = vm.sessions[0]

        try await vm.updateSessionTitle(session, title: "My Custom Title")

        // Verify in-memory update
        XCTAssertEqual(vm.sessions[0].title, "My Custom Title")

        // Verify persisted
        try await db.dbWriter.read { dbConn in
            let fetched = try ChatSession.fetchOne(dbConn, key: session.id)
            XCTAssertEqual(fetched?.title, "My Custom Title")
        }
    }

    // MARK: - Helpers

    private func makeViewModel() async throws -> (ChatSessionListViewModel, AppDatabase, Workspace) {
        let db = try TestDatabase.make()
        var workspace = Workspace(name: "Test")
        try await db.dbWriter.write { dbConn in
            try workspace.insert(dbConn)
        }
        let vm = ChatSessionListViewModel(database: db, workspaceId: workspace.id!)
        return (vm, db, workspace)
    }
}
