import XCTest
import GRDB
@testable import hydra

final class IssueTests: XCTestCase {

    private func makeProjectAndDB() throws -> (AppDatabase, Project) {
        let db = try TestDatabase.make()
        var project = Project(name: "Test")
        try db.dbWriter.write { dbConn in
            try project.insert(dbConn)
        }
        return (db, project)
    }

    func testCreateIssue() throws {
        let (db, project) = try makeProjectAndDB()
        try db.dbWriter.write { dbConn in
            var issue = hydra.Issue(projectId: project.id!, title: "Fix login bug")
            try issue.insert(dbConn)

            XCTAssertNotNil(issue.id)
            XCTAssertEqual(issue.title, "Fix login bug")
            XCTAssertEqual(issue.status, .backlog)
            XCTAssertEqual(issue.priority, .medium)
            XCTAssertEqual(issue.assigneeType, "human")
        }
    }

    func testIssueDefaults() throws {
        let issue = hydra.Issue(projectId: 1, title: "Test")
        XCTAssertEqual(issue.status, .backlog)
        XCTAssertEqual(issue.priority, .medium)
        XCTAssertEqual(issue.assigneeType, "human")
        XCTAssertEqual(issue.assigneeName, "")
        XCTAssertEqual(issue.description, "")
        XCTAssertNil(issue.epicId)
        XCTAssertNil(issue.autonomyMode)
    }

    func testUpdateIssueStatus() throws {
        let (db, project) = try makeProjectAndDB()
        try db.dbWriter.write { dbConn in
            var issue = hydra.Issue(projectId: project.id!, title: "Task")
            try issue.insert(dbConn)

            issue.status = .inProgress
            try issue.update(dbConn)

            let fetched = try hydra.Issue.fetchOne(dbConn, key: issue.id)
            XCTAssertEqual(fetched?.status, .inProgress)
        }
    }

    func testUpdateIssuePriority() throws {
        let (db, project) = try makeProjectAndDB()
        try db.dbWriter.write { dbConn in
            var issue = hydra.Issue(projectId: project.id!, title: "Urgent task", priority: .low)
            try issue.insert(dbConn)

            issue.priority = .urgent
            try issue.update(dbConn)

            let fetched = try hydra.Issue.fetchOne(dbConn, key: issue.id)
            XCTAssertEqual(fetched?.priority, .urgent)
        }
    }

    func testAssignIssueToAgent() throws {
        let (db, project) = try makeProjectAndDB()
        try db.dbWriter.write { dbConn in
            var issue = hydra.Issue(projectId: project.id!, title: "Agent task")
            try issue.insert(dbConn)

            issue.assigneeType = "agent"
            try issue.update(dbConn)

            let fetched = try hydra.Issue.fetchOne(dbConn, key: issue.id)
            XCTAssertEqual(fetched?.isAgentAssigned, true)
        }
    }

    func testIsAgentAssigned() throws {
        let agentIssue = hydra.Issue(projectId: 1, title: "A", assigneeType: "agent")
        XCTAssertTrue(agentIssue.isAgentAssigned)

        let humanIssue = hydra.Issue(projectId: 1, title: "B", assigneeType: "human")
        XCTAssertFalse(humanIssue.isAgentAssigned)
    }

    func testDeleteIssue() throws {
        let (db, project) = try makeProjectAndDB()
        try db.dbWriter.write { dbConn in
            var issue = hydra.Issue(projectId: project.id!, title: "To delete")
            try issue.insert(dbConn)
            let id = issue.id

            _ = try issue.delete(dbConn)

            let fetched = try hydra.Issue.fetchOne(dbConn, key: id)
            XCTAssertNil(fetched)
        }
    }

    func testFetchIssuesByStatus() throws {
        let (db, project) = try makeProjectAndDB()
        try db.dbWriter.write { dbConn in
            var issue1 = hydra.Issue(projectId: project.id!, title: "Backlog 1")
            var issue2 = hydra.Issue(projectId: project.id!, title: "Backlog 2")
            var issue3 = hydra.Issue(projectId: project.id!, title: "In Progress", status: .inProgress)
            try issue1.insert(dbConn)
            try issue2.insert(dbConn)
            try issue3.insert(dbConn)

            let backlogIssues = try hydra.Issue
                .filter(hydra.Issue.Columns.status == hydra.Issue.Status.backlog.rawValue)
                .fetchAll(dbConn)
            XCTAssertEqual(backlogIssues.count, 2)

            let inProgressIssues = try hydra.Issue
                .filter(hydra.Issue.Columns.status == hydra.Issue.Status.inProgress.rawValue)
                .fetchAll(dbConn)
            XCTAssertEqual(inProgressIssues.count, 1)
        }
    }

    func testIssueStatusTransitions() throws {
        let (db, project) = try makeProjectAndDB()
        try db.dbWriter.write { dbConn in
            var issue = hydra.Issue(projectId: project.id!, title: "Flow test")
            try issue.insert(dbConn)
            XCTAssertEqual(issue.status, .backlog)

            issue.status = .inProgress
            try issue.update(dbConn)

            issue.status = .inReview
            try issue.update(dbConn)

            issue.status = .done
            try issue.update(dbConn)

            let fetched = try hydra.Issue.fetchOne(dbConn, key: issue.id)
            XCTAssertEqual(fetched?.status, .done)
        }
    }

    func testCascadeDeleteWithProject() throws {
        let (db, project) = try makeProjectAndDB()
        try db.dbWriter.write { dbConn in
            var issue = hydra.Issue(projectId: project.id!, title: "Orphan test")
            try issue.insert(dbConn)
            let issueId = issue.id

            _ = try Project.deleteAll(dbConn)

            let fetched = try hydra.Issue.fetchOne(dbConn, key: issueId)
            XCTAssertNil(fetched)
        }
    }
}
