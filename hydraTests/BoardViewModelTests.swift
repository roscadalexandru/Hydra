import XCTest
import GRDB
@testable import hydra

final class BoardViewModelTests: XCTestCase {

    func testInitWithWorkspaceIdObservesIssues() throws {
        let db = try TestDatabase.make()
        var ws1 = Workspace(name: "Target")
        var ws2 = Workspace(name: "Other")
        try db.dbWriter.write { dbConn in
            try ws1.insert(dbConn)
            try ws2.insert(dbConn)
            // Insert issue in other workspace only
            var issue = Issue(workspaceId: ws2.id!, title: "Other Issue")
            try issue.insert(dbConn)
        }

        let vm = BoardViewModel(workspaceId: ws1.id!, database: db)

        // Wait for observation to deliver — after delivery, ws1 should still have 0 issues
        // We verify observation ran by checking it didn't pick up ws2's issue
        let pred = NSPredicate { _, _ in vm.issues.isEmpty }
        let exp = XCTNSPredicateExpectation(predicate: pred, object: nil)
        wait(for: [exp], timeout: 2.0)

        // Now insert an issue in ws1 and verify observation picks it up
        try db.dbWriter.write { dbConn in
            var issue = Issue(workspaceId: ws1.id!, title: "Target Issue")
            try issue.insert(dbConn)
        }

        let pred2 = NSPredicate { _, _ in vm.issues.count == 1 }
        let exp2 = XCTNSPredicateExpectation(predicate: pred2, object: nil)
        wait(for: [exp2], timeout: 2.0)

        XCTAssertEqual(vm.issues.count, 1)
        XCTAssertEqual(vm.issues.first?.title, "Target Issue")
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
