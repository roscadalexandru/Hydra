import XCTest
import GRDB
@testable import hydra

final class WelcomeViewModelTests: XCTestCase {

    func testObservesAllWorkspaces() throws {
        let db = try TestDatabase.make()
        try db.dbWriter.write { dbConn in
            var ws1 = Workspace(name: "First")
            try ws1.insert(dbConn)
            var ws2 = Workspace(name: "Second")
            try ws2.insert(dbConn)
        }

        let vm = WelcomeViewModel(database: db)

        let pred = NSPredicate { _, _ in vm.workspaces.count == 2 }
        let exp = XCTNSPredicateExpectation(predicate: pred, object: nil)
        wait(for: [exp], timeout: 2.0)

        XCTAssertEqual(vm.workspaces.count, 2)
    }

    func testWorkspacesSortedByLastOpenedAtDescending() throws {
        let db = try TestDatabase.make()
        let earlier = Date(timeIntervalSinceNow: -100)
        let later = Date()
        try db.dbWriter.write { dbConn in
            var ws1 = Workspace(name: "Old", lastOpenedAt: earlier)
            try ws1.insert(dbConn)
            var ws2 = Workspace(name: "Recent", lastOpenedAt: later)
            try ws2.insert(dbConn)
            var ws3 = Workspace(name: "Never Opened")
            try ws3.insert(dbConn)
        }

        let vm = WelcomeViewModel(database: db)

        let pred = NSPredicate { _, _ in vm.workspaces.count == 3 }
        let exp = XCTNSPredicateExpectation(predicate: pred, object: nil)
        wait(for: [exp], timeout: 2.0)

        XCTAssertEqual(vm.workspaces.count, 3)
        XCTAssertEqual(vm.workspaces[0].name, "Recent")
        XCTAssertEqual(vm.workspaces[1].name, "Old")
        XCTAssertEqual(vm.workspaces[2].name, "Never Opened")
    }

    func testCreateWorkspaceReturnsId() throws {
        let db = try TestDatabase.make()
        let vm = WelcomeViewModel(database: db)

        let id = vm.createWorkspace(name: "New Project")

        XCTAssertNotNil(id)

        let count = try db.dbWriter.read { dbConn in
            try Workspace.fetchCount(dbConn)
        }
        XCTAssertEqual(count, 1)
    }

    func testUpdateLastOpened() throws {
        let db = try TestDatabase.make()
        var workspace = Workspace(name: "Test")
        try db.dbWriter.write { dbConn in
            try workspace.insert(dbConn)
        }
        XCTAssertNil(workspace.lastOpenedAt)

        let workspaceId = try XCTUnwrap(workspace.id)
        let vm = WelcomeViewModel(database: db)
        vm.updateLastOpened(workspaceId)

        let fetched = try db.dbWriter.read { dbConn in
            try Workspace.fetchOne(dbConn, key: workspace.id)
        }
        XCTAssertNotNil(fetched?.lastOpenedAt)
    }

    func testDeleteWorkspace() throws {
        let db = try TestDatabase.make()
        var workspace = Workspace(name: "To Delete")
        try db.dbWriter.write { dbConn in
            try workspace.insert(dbConn)
        }

        let workspaceId = try XCTUnwrap(workspace.id)
        let vm = WelcomeViewModel(database: db)
        vm.deleteWorkspace(workspaceId)

        let count = try db.dbWriter.read { dbConn in
            try Workspace.fetchCount(dbConn)
        }
        XCTAssertEqual(count, 0)
    }
}
