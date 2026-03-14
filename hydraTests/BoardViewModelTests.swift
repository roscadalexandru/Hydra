import XCTest
import GRDB
@testable import hydra

final class BoardViewModelTests: XCTestCase {

    func testInitWithWorkspaceIdObservesIssues() throws {
        let db = try TestDatabase.make()
        var workspace = Workspace(name: "Test")
        try db.dbWriter.write { dbConn in
            try workspace.insert(dbConn)
        }

        let vm = BoardViewModel(workspaceId: workspace.id!, database: db)

        let pred = NSPredicate { _, _ in vm.issues.count == 0 }
        let exp = XCTNSPredicateExpectation(predicate: pred, object: nil)
        wait(for: [exp], timeout: 2.0)

        XCTAssertEqual(vm.issues.count, 0)
    }

    func testCreateIssueUsesWorkspaceId() throws {
        let db = try TestDatabase.make()
        var workspace = Workspace(name: "Test")
        try db.dbWriter.write { dbConn in
            try workspace.insert(dbConn)
        }

        let vm = BoardViewModel(workspaceId: workspace.id!, database: db)
        vm.createIssue(title: "My Task")

        let pred = NSPredicate { _, _ in vm.issues.count == 1 }
        let exp = XCTNSPredicateExpectation(predicate: pred, object: nil)
        wait(for: [exp], timeout: 2.0)

        XCTAssertEqual(vm.issues.count, 1)
        XCTAssertEqual(vm.issues.first?.title, "My Task")
        XCTAssertEqual(vm.issues.first?.workspaceId, workspace.id)
    }

    func testOnlyObservesIssuesForGivenWorkspace() throws {
        let db = try TestDatabase.make()
        var ws1 = Workspace(name: "WS1")
        var ws2 = Workspace(name: "WS2")
        try db.dbWriter.write { dbConn in
            try ws1.insert(dbConn)
            try ws2.insert(dbConn)
            var issue1 = Issue(workspaceId: ws1.id!, title: "WS1 Issue")
            try issue1.insert(dbConn)
            var issue2 = Issue(workspaceId: ws2.id!, title: "WS2 Issue")
            try issue2.insert(dbConn)
        }

        let vm = BoardViewModel(workspaceId: ws1.id!, database: db)

        let pred = NSPredicate { _, _ in vm.issues.count == 1 }
        let exp = XCTNSPredicateExpectation(predicate: pred, object: nil)
        wait(for: [exp], timeout: 2.0)

        XCTAssertEqual(vm.issues.count, 1)
        XCTAssertEqual(vm.issues.first?.title, "WS1 Issue")
    }
}
