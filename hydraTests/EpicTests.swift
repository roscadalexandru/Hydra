import XCTest
import GRDB
@testable import hydra

final class EpicTests: XCTestCase {

    private func makeWorkspaceAndDB() throws -> (AppDatabase, Workspace) {
        let db = try TestDatabase.make()
        var workspace = Workspace(name: "Test")
        try db.dbWriter.write { dbConn in
            try workspace.insert(dbConn)
        }
        return (db, workspace)
    }

    func testCreateEpic() throws {
        let (db, workspace) = try makeWorkspaceAndDB()
        try db.dbWriter.write { dbConn in
            var epic = Epic(workspaceId: workspace.id!, title: "Auth System")
            try epic.insert(dbConn)

            XCTAssertNotNil(epic.id)
            XCTAssertEqual(epic.title, "Auth System")
        }
    }

    func testLinkIssueToEpic() throws {
        let (db, workspace) = try makeWorkspaceAndDB()
        try db.dbWriter.write { dbConn in
            var epic = Epic(workspaceId: workspace.id!, title: "Auth")
            try epic.insert(dbConn)

            var issue = hydra.Issue(workspaceId: workspace.id!, epicId: epic.id, title: "Login page")
            try issue.insert(dbConn)

            let fetched = try hydra.Issue.fetchOne(dbConn, key: issue.id)
            XCTAssertEqual(fetched?.epicId, epic.id)
        }
    }

    func testDeleteEpicNullsIssueReference() throws {
        let (db, workspace) = try makeWorkspaceAndDB()
        try db.dbWriter.write { dbConn in
            var epic = Epic(workspaceId: workspace.id!, title: "To Delete")
            try epic.insert(dbConn)

            var issue = hydra.Issue(workspaceId: workspace.id!, epicId: epic.id, title: "Linked")
            try issue.insert(dbConn)

            _ = try epic.delete(dbConn)

            let fetched = try hydra.Issue.fetchOne(dbConn, key: issue.id)
            XCTAssertNotNil(fetched)
            XCTAssertNil(fetched?.epicId)
        }
    }

    func testCascadeDeleteWithWorkspace() throws {
        let (db, workspace) = try makeWorkspaceAndDB()
        try db.dbWriter.write { dbConn in
            var epic = Epic(workspaceId: workspace.id!, title: "Orphan test")
            try epic.insert(dbConn)
            let epicId = epic.id

            _ = try Workspace.deleteAll(dbConn)

            let fetched = try Epic.fetchOne(dbConn, key: epicId)
            XCTAssertNil(fetched)
        }
    }
}
