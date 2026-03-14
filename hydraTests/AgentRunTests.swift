import XCTest
import GRDB
@testable import hydra

final class AgentRunTests: XCTestCase {

    private func makeIssueAndDB() throws -> (AppDatabase, hydra.Issue) {
        let db = try TestDatabase.make()
        var project = Project(name: "Test")
        try db.dbWriter.write { dbConn in
            try project.insert(dbConn)
        }
        var issue = hydra.Issue(projectId: project.id!, title: "Test task")
        try db.dbWriter.write { dbConn in
            try issue.insert(dbConn)
        }
        return (db, issue)
    }

    func testCreateAgentRun() throws {
        let (db, issue) = try makeIssueAndDB()
        try db.dbWriter.write { dbConn in
            var run = AgentRun(issueId: issue.id!)
            try run.insert(dbConn)

            XCTAssertNotNil(run.id)
            XCTAssertEqual(run.status, .running)
            XCTAssertNil(run.error)
            XCTAssertNil(run.finishedAt)
        }
    }

    func testCompleteAgentRun() throws {
        let (db, issue) = try makeIssueAndDB()
        try db.dbWriter.write { dbConn in
            var run = AgentRun(issueId: issue.id!)
            try run.insert(dbConn)

            run.status = .completed
            run.finishedAt = Date()
            try run.update(dbConn)

            let fetched = try AgentRun.fetchOne(dbConn, key: run.id)
            XCTAssertEqual(fetched?.status, .completed)
            XCTAssertNotNil(fetched?.finishedAt)
        }
    }

    func testFailAgentRun() throws {
        let (db, issue) = try makeIssueAndDB()
        try db.dbWriter.write { dbConn in
            var run = AgentRun(issueId: issue.id!)
            try run.insert(dbConn)

            run.status = .failed
            run.error = "Build failed with exit code 1"
            run.finishedAt = Date()
            try run.update(dbConn)

            let fetched = try AgentRun.fetchOne(dbConn, key: run.id)
            XCTAssertEqual(fetched?.status, .failed)
            XCTAssertEqual(fetched?.error, "Build failed with exit code 1")
        }
    }

    func testCascadeDeleteWithIssue() throws {
        let (db, issue) = try makeIssueAndDB()
        try db.dbWriter.write { dbConn in
            var run = AgentRun(issueId: issue.id!)
            try run.insert(dbConn)
            let runId = run.id

            _ = try hydra.Issue.deleteAll(dbConn)

            let fetched = try AgentRun.fetchOne(dbConn, key: runId)
            XCTAssertNil(fetched)
        }
    }
}
