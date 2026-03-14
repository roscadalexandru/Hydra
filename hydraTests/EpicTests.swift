import XCTest
import GRDB
@testable import hydra

final class EpicTests: XCTestCase {

    private func makeProjectAndDB() throws -> (AppDatabase, Project) {
        let db = try TestDatabase.make()
        var project = Project(name: "Test")
        try db.dbWriter.write { dbConn in
            try project.insert(dbConn)
        }
        return (db, project)
    }

    func testCreateEpic() throws {
        let (db, project) = try makeProjectAndDB()
        try db.dbWriter.write { dbConn in
            var epic = Epic(projectId: project.id!, title: "Auth System")
            try epic.insert(dbConn)

            XCTAssertNotNil(epic.id)
            XCTAssertEqual(epic.title, "Auth System")
        }
    }

    func testLinkIssueToEpic() throws {
        let (db, project) = try makeProjectAndDB()
        try db.dbWriter.write { dbConn in
            var epic = Epic(projectId: project.id!, title: "Auth")
            try epic.insert(dbConn)

            var issue = hydra.Issue(projectId: project.id!, epicId: epic.id, title: "Login page")
            try issue.insert(dbConn)

            let fetched = try hydra.Issue.fetchOne(dbConn, key: issue.id)
            XCTAssertEqual(fetched?.epicId, epic.id)
        }
    }

    func testDeleteEpicNullsIssueReference() throws {
        let (db, project) = try makeProjectAndDB()
        try db.dbWriter.write { dbConn in
            var epic = Epic(projectId: project.id!, title: "To Delete")
            try epic.insert(dbConn)

            var issue = hydra.Issue(projectId: project.id!, epicId: epic.id, title: "Linked")
            try issue.insert(dbConn)

            _ = try epic.delete(dbConn)

            let fetched = try hydra.Issue.fetchOne(dbConn, key: issue.id)
            XCTAssertNotNil(fetched)
            XCTAssertNil(fetched?.epicId)
        }
    }

    func testCascadeDeleteWithProject() throws {
        let (db, project) = try makeProjectAndDB()
        try db.dbWriter.write { dbConn in
            var epic = Epic(projectId: project.id!, title: "Orphan test")
            try epic.insert(dbConn)
            let epicId = epic.id

            _ = try Project.deleteAll(dbConn)

            let fetched = try Epic.fetchOne(dbConn, key: epicId)
            XCTAssertNil(fetched)
        }
    }
}
