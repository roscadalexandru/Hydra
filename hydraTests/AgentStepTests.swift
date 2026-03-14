import XCTest
import GRDB
@testable import hydra

final class AgentStepTests: XCTestCase {

    private func makeRunAndDB() throws -> (AppDatabase, AgentRun) {
        let db = try TestDatabase.make()
        var project = Project(name: "Test")
        try db.dbWriter.write { dbConn in
            try project.insert(dbConn)
        }
        var issue = hydra.Issue(projectId: project.id!, title: "Task")
        try db.dbWriter.write { dbConn in
            try issue.insert(dbConn)
        }
        var run = AgentRun(issueId: issue.id!)
        try db.dbWriter.write { dbConn in
            try run.insert(dbConn)
        }
        return (db, run)
    }

    func testCreateStep() throws {
        let (db, run) = try makeRunAndDB()
        try db.dbWriter.write { dbConn in
            var step = AgentStep(agentRunId: run.id!, orderIndex: 0, description: "Read file")
            try step.insert(dbConn)

            XCTAssertNotNil(step.id)
            XCTAssertEqual(step.status, .pending)
            XCTAssertNil(step.output)
        }
    }

    func testStepLifecycle() throws {
        let (db, run) = try makeRunAndDB()
        try db.dbWriter.write { dbConn in
            var step = AgentStep(agentRunId: run.id!, orderIndex: 0, description: "Edit code")
            try step.insert(dbConn)

            step.status = .running
            step.startedAt = Date()
            try step.update(dbConn)

            step.status = .completed
            step.output = "Modified 3 files"
            step.filesChanged = "src/main.swift,src/app.swift,src/util.swift"
            step.finishedAt = Date()
            try step.update(dbConn)

            let fetched = try AgentStep.fetchOne(dbConn, key: step.id)
            XCTAssertEqual(fetched?.status, .completed)
            XCTAssertEqual(fetched?.output, "Modified 3 files")
            XCTAssertTrue(fetched?.filesChanged?.contains("main.swift") == true)
        }
    }

    func testMultipleStepsOrdered() throws {
        let (db, run) = try makeRunAndDB()
        try db.dbWriter.write { dbConn in
            var step1 = AgentStep(agentRunId: run.id!, orderIndex: 0, description: "Read")
            var step2 = AgentStep(agentRunId: run.id!, orderIndex: 1, description: "Plan")
            var step3 = AgentStep(agentRunId: run.id!, orderIndex: 2, description: "Execute")
            try step1.insert(dbConn)
            try step2.insert(dbConn)
            try step3.insert(dbConn)

            let steps = try AgentStep
                .filter(AgentStep.Columns.agentRunId == run.id!)
                .order(AgentStep.Columns.orderIndex.asc)
                .fetchAll(dbConn)

            XCTAssertEqual(steps.count, 3)
            XCTAssertEqual(steps[0].description, "Read")
            XCTAssertEqual(steps[1].description, "Plan")
            XCTAssertEqual(steps[2].description, "Execute")
        }
    }

    func testCascadeDeleteWithRun() throws {
        let (db, run) = try makeRunAndDB()
        try db.dbWriter.write { dbConn in
            var step = AgentStep(agentRunId: run.id!, orderIndex: 0, description: "Step")
            try step.insert(dbConn)
            let stepId = step.id

            _ = try AgentRun.deleteAll(dbConn)

            let fetched = try AgentStep.fetchOne(dbConn, key: stepId)
            XCTAssertNil(fetched)
        }
    }
}
