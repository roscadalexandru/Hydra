import XCTest
import GRDB
@testable import hydra

final class WorkspaceSettingsViewModelTests: XCTestCase {

    // MARK: - Workspace Observation

    func testObservesWorkspaceById() throws {
        let db = try TestDatabase.make()
        var workspace = Workspace(name: "My Workspace", description: "A desc")
        try db.dbWriter.write { dbConn in
            try workspace.insert(dbConn)
        }

        let workspaceId = try XCTUnwrap(workspace.id)
        let vm = WorkspaceSettingsViewModel(workspaceId: workspaceId, database: db)

        let pred = NSPredicate { _, _ in vm.workspace != nil }
        let exp = XCTNSPredicateExpectation(predicate: pred, object: nil)
        wait(for: [exp], timeout: 2.0)

        XCTAssertEqual(vm.workspace?.name, "My Workspace")
        XCTAssertEqual(vm.workspace?.description, "A desc")
        XCTAssertEqual(vm.workspace?.defaultAutonomyMode, .supervised)
    }

    // MARK: - Update Workspace

    func testUpdateWorkspaceName() throws {
        let db = try TestDatabase.make()
        var workspace = Workspace(name: "Old Name")
        try db.dbWriter.write { dbConn in
            try workspace.insert(dbConn)
        }

        let workspaceId = try XCTUnwrap(workspace.id)
        let vm = WorkspaceSettingsViewModel(workspaceId: workspaceId, database: db)

        let loaded = NSPredicate { _, _ in vm.workspace != nil }
        wait(for: [XCTNSPredicateExpectation(predicate: loaded, object: nil)], timeout: 2.0)

        vm.updateWorkspace(name: "New Name")

        let pred = NSPredicate { _, _ in vm.workspace?.name == "New Name" }
        let exp = XCTNSPredicateExpectation(predicate: pred, object: nil)
        wait(for: [exp], timeout: 2.0)

        let fetched = try db.dbWriter.read { dbConn in
            try Workspace.fetchOne(dbConn, key: workspaceId)
        }
        XCTAssertEqual(fetched?.name, "New Name")
    }

    func testUpdateWorkspaceDescription() throws {
        let db = try TestDatabase.make()
        var workspace = Workspace(name: "WS")
        try db.dbWriter.write { dbConn in
            try workspace.insert(dbConn)
        }

        let workspaceId = try XCTUnwrap(workspace.id)
        let vm = WorkspaceSettingsViewModel(workspaceId: workspaceId, database: db)

        let loaded = NSPredicate { _, _ in vm.workspace != nil }
        wait(for: [XCTNSPredicateExpectation(predicate: loaded, object: nil)], timeout: 2.0)

        vm.updateWorkspace(description: "Updated description")

        let pred = NSPredicate { _, _ in vm.workspace?.description == "Updated description" }
        let exp = XCTNSPredicateExpectation(predicate: pred, object: nil)
        wait(for: [exp], timeout: 2.0)

        let fetched = try db.dbWriter.read { dbConn in
            try Workspace.fetchOne(dbConn, key: workspaceId)
        }
        XCTAssertEqual(fetched?.description, "Updated description")
    }

    func testUpdateWorkspaceAutonomyMode() throws {
        let db = try TestDatabase.make()
        var workspace = Workspace(name: "WS")
        try db.dbWriter.write { dbConn in
            try workspace.insert(dbConn)
        }

        let workspaceId = try XCTUnwrap(workspace.id)
        let vm = WorkspaceSettingsViewModel(workspaceId: workspaceId, database: db)

        let loaded = NSPredicate { _, _ in vm.workspace != nil }
        wait(for: [XCTNSPredicateExpectation(predicate: loaded, object: nil)], timeout: 2.0)

        vm.updateWorkspace(autonomyMode: .autonomous)

        let pred = NSPredicate { _, _ in vm.workspace?.defaultAutonomyMode == .autonomous }
        let exp = XCTNSPredicateExpectation(predicate: pred, object: nil)
        wait(for: [exp], timeout: 2.0)

        let fetched = try db.dbWriter.read { dbConn in
            try Workspace.fetchOne(dbConn, key: workspaceId)
        }
        XCTAssertEqual(fetched?.defaultAutonomyMode, .autonomous)
    }

    // MARK: - Project Observation

    func testObservesProjectsForWorkspace() throws {
        let db = try TestDatabase.make()
        var workspace = Workspace(name: "WS")
        try db.dbWriter.write { dbConn in
            try workspace.insert(dbConn)
            let wsId = try XCTUnwrap(workspace.id)
            var p1 = Project(workspaceId: wsId, name: "frontend", path: "/code/frontend")
            try p1.insert(dbConn)
            var p2 = Project(workspaceId: wsId, name: "backend", path: "/code/backend")
            try p2.insert(dbConn)
        }

        let workspaceId = try XCTUnwrap(workspace.id)
        let vm = WorkspaceSettingsViewModel(workspaceId: workspaceId, database: db)

        let pred = NSPredicate { _, _ in vm.projects.count == 2 }
        let exp = XCTNSPredicateExpectation(predicate: pred, object: nil)
        wait(for: [exp], timeout: 2.0)

        XCTAssertEqual(vm.projects.count, 2)
    }

    func testOnlyObservesProjectsForGivenWorkspace() throws {
        let db = try TestDatabase.make()
        var ws1 = Workspace(name: "WS1")
        var ws2 = Workspace(name: "WS2")
        try db.dbWriter.write { dbConn in
            try ws1.insert(dbConn)
            try ws2.insert(dbConn)
            let ws1Id = try XCTUnwrap(ws1.id)
            let ws2Id = try XCTUnwrap(ws2.id)
            var p1 = Project(workspaceId: ws1Id, name: "mine", path: "/mine")
            try p1.insert(dbConn)
            var p2 = Project(workspaceId: ws2Id, name: "theirs", path: "/theirs")
            try p2.insert(dbConn)
        }

        let ws1Id = try XCTUnwrap(ws1.id)
        let vm = WorkspaceSettingsViewModel(workspaceId: ws1Id, database: db)

        let pred = NSPredicate { _, _ in vm.projects.count == 1 }
        let exp = XCTNSPredicateExpectation(predicate: pred, object: nil)
        wait(for: [exp], timeout: 2.0)

        XCTAssertEqual(vm.projects.count, 1)
        XCTAssertEqual(vm.projects.first?.name, "mine")
    }

    // MARK: - Add Project

    func testAddProject() throws {
        let db = try TestDatabase.make()
        var workspace = Workspace(name: "WS")
        try db.dbWriter.write { dbConn in
            try workspace.insert(dbConn)
        }

        let workspaceId = try XCTUnwrap(workspace.id)
        let vm = WorkspaceSettingsViewModel(workspaceId: workspaceId, database: db)

        vm.addProject(name: "new-app", path: "/code/new-app")

        let pred = NSPredicate { _, _ in vm.projects.count == 1 }
        let exp = XCTNSPredicateExpectation(predicate: pred, object: nil)
        wait(for: [exp], timeout: 2.0)

        XCTAssertEqual(vm.projects.first?.name, "new-app")
        XCTAssertEqual(vm.projects.first?.path, "/code/new-app")
        XCTAssertEqual(vm.projects.first?.workspaceId, workspaceId)
    }

    // MARK: - Remove Project

    func testRemoveProject() throws {
        let db = try TestDatabase.make()
        var workspace = Workspace(name: "WS")
        try db.dbWriter.write { dbConn in
            try workspace.insert(dbConn)
            let wsId = try XCTUnwrap(workspace.id)
            var project = Project(workspaceId: wsId, name: "to-remove", path: "/code/to-remove")
            try project.insert(dbConn)
        }

        let workspaceId = try XCTUnwrap(workspace.id)
        let vm = WorkspaceSettingsViewModel(workspaceId: workspaceId, database: db)

        let loaded = NSPredicate { _, _ in vm.projects.count == 1 }
        wait(for: [XCTNSPredicateExpectation(predicate: loaded, object: nil)], timeout: 2.0)

        let projectId = try XCTUnwrap(vm.projects.first?.id)
        vm.removeProject(projectId)

        let pred = NSPredicate { _, _ in vm.projects.isEmpty }
        let exp = XCTNSPredicateExpectation(predicate: pred, object: nil)
        wait(for: [exp], timeout: 2.0)

        let count = try db.dbWriter.read { dbConn in
            try Project.filter(Project.Columns.workspaceId == workspaceId).fetchCount(dbConn)
        }
        XCTAssertEqual(count, 0)
    }

    // MARK: - Live Observation

    func testProjectObservationUpdatesWhenProjectAdded() throws {
        let db = try TestDatabase.make()
        var workspace = Workspace(name: "WS")
        try db.dbWriter.write { dbConn in
            try workspace.insert(dbConn)
        }

        let workspaceId = try XCTUnwrap(workspace.id)
        let vm = WorkspaceSettingsViewModel(workspaceId: workspaceId, database: db)

        // Wait for initial empty state
        let empty = NSPredicate { _, _ in vm.workspace != nil }
        wait(for: [XCTNSPredicateExpectation(predicate: empty, object: nil)], timeout: 2.0)
        XCTAssertTrue(vm.projects.isEmpty)

        // Insert externally
        try db.dbWriter.write { dbConn in
            var project = Project(workspaceId: workspaceId, name: "external", path: "/ext")
            try project.insert(dbConn)
        }

        let pred = NSPredicate { _, _ in vm.projects.count == 1 }
        let exp = XCTNSPredicateExpectation(predicate: pred, object: nil)
        wait(for: [exp], timeout: 2.0)

        XCTAssertEqual(vm.projects.first?.name, "external")
    }
}
