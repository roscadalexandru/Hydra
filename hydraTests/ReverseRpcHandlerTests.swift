import XCTest
import GRDB
@testable import hydra

final class ReverseRpcHandlerTests: XCTestCase {

    private var database: AppDatabase!
    private var handler: ReverseRpcHandler!
    private var workspaceId: Int64!

    override func setUp() async throws {
        database = try TestDatabase.make()
        handler = ReverseRpcHandler(database: database)
        // Create a workspace to scope all operations
        var workspace = Workspace(name: "Test WS")
        try await database.dbWriter.write { db in
            try workspace.insert(db)
        }
        workspaceId = workspace.id!
    }

    // MARK: - create_issue

    func testCreateIssueReturnsIssueWithId() async throws {
        let params = AnyCodableValue.dictionary([
            "workspaceId": .number(Double(workspaceId)),
            "title": .string("Fix login bug"),
            "description": .string("Users can't log in"),
            "priority": .string("high"),
        ])

        let result = try await handler.handle(method: "db.create_issue", params: params)

        if case .dictionary(let dict) = result {
            XCTAssertNotNil(dict["id"])
            XCTAssertEqual(dict["title"], .string("Fix login bug"))
            XCTAssertEqual(dict["description"], .string("Users can't log in"))
            XCTAssertEqual(dict["priority"], .string("high"))
            XCTAssertEqual(dict["status"], .string("backlog"))
        } else {
            XCTFail("Expected dictionary result, got \(result)")
        }
    }

    func testCreateIssueWithEpic() async throws {
        var epic = Epic(workspaceId: workspaceId, title: "Auth")
        try await database.dbWriter.write { db in try epic.insert(db) }

        let params = AnyCodableValue.dictionary([
            "workspaceId": .number(Double(workspaceId)),
            "title": .string("Fix auth token"),
            "epicId": .number(Double(epic.id!)),
        ])

        let result = try await handler.handle(method: "db.create_issue", params: params)

        if case .dictionary(let dict) = result {
            XCTAssertEqual(dict["epicId"], .number(Double(epic.id!)))
        } else {
            XCTFail("Expected dictionary result")
        }
    }

    func testCreateIssueRequiresTitle() async throws {
        let params = AnyCodableValue.dictionary([
            "workspaceId": .number(Double(workspaceId)),
        ])

        do {
            _ = try await handler.handle(method: "db.create_issue", params: params)
            XCTFail("Expected error")
        } catch let error as ReverseRpcHandlerError {
            XCTAssertEqual(error, .missingRequiredField("title"))
        }
    }

    // MARK: - get_issue

    func testGetIssueReturnsFullDetails() async throws {
        var issue = hydra.Issue(workspaceId: workspaceId, title: "Test issue", description: "Details")
        try await database.dbWriter.write { db in try issue.insert(db) }

        let params = AnyCodableValue.dictionary([
            "id": .number(Double(issue.id!)),
            "workspaceId": .number(Double(workspaceId)),
        ])

        let result = try await handler.handle(method: "db.get_issue", params: params)

        if case .dictionary(let dict) = result {
            XCTAssertEqual(dict["id"], .number(Double(issue.id!)))
            XCTAssertEqual(dict["title"], .string("Test issue"))
            XCTAssertEqual(dict["description"], .string("Details"))
        } else {
            XCTFail("Expected dictionary result")
        }
    }

    func testGetIssueReturnsErrorForInvalidId() async throws {
        let params = AnyCodableValue.dictionary([
            "id": .number(999),
            "workspaceId": .number(Double(workspaceId)),
        ])

        do {
            _ = try await handler.handle(method: "db.get_issue", params: params)
            XCTFail("Expected error")
        } catch let error as ReverseRpcHandlerError {
            XCTAssertEqual(error, .notFound("Issue", 999))
        }
    }

    // MARK: - list_issues

    func testListIssuesReturnsAllForWorkspace() async throws {
        try await database.dbWriter.write { db in
            var i1 = hydra.Issue(workspaceId: workspaceId, title: "Issue 1")
            var i2 = hydra.Issue(workspaceId: workspaceId, title: "Issue 2")
            try i1.insert(db)
            try i2.insert(db)
        }

        let params = AnyCodableValue.dictionary([
            "workspaceId": .number(Double(workspaceId)),
        ])

        let result = try await handler.handle(method: "db.list_issues", params: params)

        if case .array(let issues) = result {
            XCTAssertEqual(issues.count, 2)
        } else {
            XCTFail("Expected array result")
        }
    }

    func testListIssuesFiltersByStatus() async throws {
        try await database.dbWriter.write { db in
            var i1 = hydra.Issue(workspaceId: workspaceId, title: "Backlog", status: .backlog)
            var i2 = hydra.Issue(workspaceId: workspaceId, title: "Done", status: .done)
            try i1.insert(db)
            try i2.insert(db)
        }

        let params = AnyCodableValue.dictionary([
            "workspaceId": .number(Double(workspaceId)),
            "status": .string("backlog"),
        ])

        let result = try await handler.handle(method: "db.list_issues", params: params)

        if case .array(let issues) = result {
            XCTAssertEqual(issues.count, 1)
            if case .dictionary(let dict) = issues[0] {
                XCTAssertEqual(dict["title"], .string("Backlog"))
            }
        } else {
            XCTFail("Expected array result")
        }
    }

    func testListIssuesFiltersByEpicId() async throws {
        var epic = Epic(workspaceId: workspaceId, title: "Auth")
        try await database.dbWriter.write { db in
            try epic.insert(db)
            var i1 = hydra.Issue(workspaceId: workspaceId, epicId: epic.id, title: "In epic")
            var i2 = hydra.Issue(workspaceId: workspaceId, title: "No epic")
            try i1.insert(db)
            try i2.insert(db)
        }

        let params = AnyCodableValue.dictionary([
            "workspaceId": .number(Double(workspaceId)),
            "epicId": .number(Double(epic.id!)),
        ])

        let result = try await handler.handle(method: "db.list_issues", params: params)

        if case .array(let issues) = result {
            XCTAssertEqual(issues.count, 1)
        } else {
            XCTFail("Expected array result")
        }
    }

    func testListIssuesFiltersByPriority() async throws {
        try await database.dbWriter.write { db in
            var i1 = hydra.Issue(workspaceId: workspaceId, title: "Urgent", priority: .urgent)
            var i2 = hydra.Issue(workspaceId: workspaceId, title: "Low", priority: .low)
            try i1.insert(db)
            try i2.insert(db)
        }

        let params = AnyCodableValue.dictionary([
            "workspaceId": .number(Double(workspaceId)),
            "priority": .string("urgent"),
        ])

        let result = try await handler.handle(method: "db.list_issues", params: params)

        if case .array(let issues) = result {
            XCTAssertEqual(issues.count, 1)
        } else {
            XCTFail("Expected array result")
        }
    }

    func testListIssuesFiltersByAssigneeType() async throws {
        try await database.dbWriter.write { db in
            var i1 = hydra.Issue(workspaceId: workspaceId, title: "Agent task", assigneeType: "agent")
            var i2 = hydra.Issue(workspaceId: workspaceId, title: "Human task", assigneeType: "human")
            try i1.insert(db)
            try i2.insert(db)
        }

        let params = AnyCodableValue.dictionary([
            "workspaceId": .number(Double(workspaceId)),
            "assigneeType": .string("agent"),
        ])

        let result = try await handler.handle(method: "db.list_issues", params: params)

        if case .array(let issues) = result {
            XCTAssertEqual(issues.count, 1)
        } else {
            XCTFail("Expected array result")
        }
    }

    // MARK: - update_issue

    func testUpdateIssueChangesFields() async throws {
        var issue = hydra.Issue(workspaceId: workspaceId, title: "Old title", status: .backlog)
        try await database.dbWriter.write { db in try issue.insert(db) }

        let params = AnyCodableValue.dictionary([
            "id": .number(Double(issue.id!)),
            "workspaceId": .number(Double(workspaceId)),
            "title": .string("New title"),
            "status": .string("in_progress"),
            "priority": .string("urgent"),
        ])

        let result = try await handler.handle(method: "db.update_issue", params: params)

        if case .dictionary(let dict) = result {
            XCTAssertEqual(dict["title"], .string("New title"))
            XCTAssertEqual(dict["status"], .string("in_progress"))
            XCTAssertEqual(dict["priority"], .string("urgent"))
        } else {
            XCTFail("Expected dictionary result")
        }

        // Verify in DB
        let updated = try await database.dbWriter.read { db in
            try hydra.Issue.fetchOne(db, id: issue.id!)
        }
        XCTAssertEqual(updated?.title, "New title")
        XCTAssertEqual(updated?.status, .inProgress)
    }

    func testUpdateIssueReturnsErrorForInvalidId() async throws {
        let params = AnyCodableValue.dictionary([
            "id": .number(999),
            "workspaceId": .number(Double(workspaceId)),
            "title": .string("Doesn't matter"),
        ])

        do {
            _ = try await handler.handle(method: "db.update_issue", params: params)
            XCTFail("Expected error")
        } catch let error as ReverseRpcHandlerError {
            XCTAssertEqual(error, .notFound("Issue", 999))
        }
    }

    // MARK: - delete_issue

    func testDeleteIssueRemovesFromDatabase() async throws {
        var issue = hydra.Issue(workspaceId: workspaceId, title: "To delete")
        try await database.dbWriter.write { db in try issue.insert(db) }

        let params = AnyCodableValue.dictionary([
            "id": .number(Double(issue.id!)),
            "workspaceId": .number(Double(workspaceId)),
        ])

        let result = try await handler.handle(method: "db.delete_issue", params: params)

        if case .dictionary(let dict) = result {
            XCTAssertEqual(dict["deleted"], .bool(true))
        } else {
            XCTFail("Expected dictionary result")
        }

        // Verify removed from DB
        let deleted = try await database.dbWriter.read { db in
            try hydra.Issue.fetchOne(db, id: issue.id!)
        }
        XCTAssertNil(deleted)
    }

    func testDeleteIssueReturnsErrorForInvalidId() async throws {
        let params = AnyCodableValue.dictionary([
            "id": .number(999),
            "workspaceId": .number(Double(workspaceId)),
        ])

        do {
            _ = try await handler.handle(method: "db.delete_issue", params: params)
            XCTFail("Expected error")
        } catch let error as ReverseRpcHandlerError {
            XCTAssertEqual(error, .notFound("Issue", 999))
        }
    }

    // MARK: - list_epics

    func testListEpicsReturnsAllForWorkspace() async throws {
        try await database.dbWriter.write { db in
            var e1 = Epic(workspaceId: workspaceId, title: "Auth")
            var e2 = Epic(workspaceId: workspaceId, title: "UI")
            try e1.insert(db)
            try e2.insert(db)
        }

        let params = AnyCodableValue.dictionary([
            "workspaceId": .number(Double(workspaceId)),
        ])

        let result = try await handler.handle(method: "db.list_epics", params: params)

        if case .array(let epics) = result {
            XCTAssertEqual(epics.count, 2)
        } else {
            XCTFail("Expected array result")
        }
    }

    // MARK: - create_epic

    func testCreateEpicReturnsEpicWithId() async throws {
        let params = AnyCodableValue.dictionary([
            "workspaceId": .number(Double(workspaceId)),
            "title": .string("Auth System"),
            "description": .string("Authentication and authorization"),
        ])

        let result = try await handler.handle(method: "db.create_epic", params: params)

        if case .dictionary(let dict) = result {
            XCTAssertNotNil(dict["id"])
            XCTAssertEqual(dict["title"], .string("Auth System"))
            XCTAssertEqual(dict["description"], .string("Authentication and authorization"))
        } else {
            XCTFail("Expected dictionary result")
        }
    }

    func testCreateEpicRequiresTitle() async throws {
        let params = AnyCodableValue.dictionary([
            "workspaceId": .number(Double(workspaceId)),
        ])

        do {
            _ = try await handler.handle(method: "db.create_epic", params: params)
            XCTFail("Expected error")
        } catch let error as ReverseRpcHandlerError {
            XCTAssertEqual(error, .missingRequiredField("title"))
        }
    }

    // MARK: - update_epic

    func testUpdateEpicChangesFields() async throws {
        var epic = Epic(workspaceId: workspaceId, title: "Old title")
        try await database.dbWriter.write { db in try epic.insert(db) }

        let params = AnyCodableValue.dictionary([
            "id": .number(Double(epic.id!)),
            "workspaceId": .number(Double(workspaceId)),
            "title": .string("New title"),
            "description": .string("Updated desc"),
        ])

        let result = try await handler.handle(method: "db.update_epic", params: params)

        if case .dictionary(let dict) = result {
            XCTAssertEqual(dict["title"], .string("New title"))
            XCTAssertEqual(dict["description"], .string("Updated desc"))
        } else {
            XCTFail("Expected dictionary result")
        }
    }

    func testUpdateEpicReturnsErrorForInvalidId() async throws {
        let params = AnyCodableValue.dictionary([
            "id": .number(999),
            "workspaceId": .number(Double(workspaceId)),
            "title": .string("Doesn't matter"),
        ])

        do {
            _ = try await handler.handle(method: "db.update_epic", params: params)
            XCTFail("Expected error")
        } catch let error as ReverseRpcHandlerError {
            XCTAssertEqual(error, .notFound("Epic", 999))
        }
    }

    // MARK: - Workspace isolation

    func testGetIssueRejectsIssueFromOtherWorkspace() async throws {
        // Create issue in a different workspace
        var otherWs = Workspace(name: "Other WS")
        try await database.dbWriter.write { db in try otherWs.insert(db) }
        var issue = hydra.Issue(workspaceId: otherWs.id!, title: "Other WS issue")
        try await database.dbWriter.write { db in try issue.insert(db) }

        let params = AnyCodableValue.dictionary([
            "id": .number(Double(issue.id!)),
            "workspaceId": .number(Double(workspaceId)),
        ])

        do {
            _ = try await handler.handle(method: "db.get_issue", params: params)
            XCTFail("Expected error — should not access other workspace's issue")
        } catch let error as ReverseRpcHandlerError {
            XCTAssertEqual(error, .notFound("Issue", issue.id!))
        }
    }

    func testUpdateIssueRejectsIssueFromOtherWorkspace() async throws {
        var otherWs = Workspace(name: "Other WS")
        try await database.dbWriter.write { db in try otherWs.insert(db) }
        var issue = hydra.Issue(workspaceId: otherWs.id!, title: "Other WS issue")
        try await database.dbWriter.write { db in try issue.insert(db) }

        let params = AnyCodableValue.dictionary([
            "id": .number(Double(issue.id!)),
            "workspaceId": .number(Double(workspaceId)),
            "title": .string("Hacked"),
        ])

        do {
            _ = try await handler.handle(method: "db.update_issue", params: params)
            XCTFail("Expected error — should not modify other workspace's issue")
        } catch let error as ReverseRpcHandlerError {
            XCTAssertEqual(error, .notFound("Issue", issue.id!))
        }
    }

    func testDeleteIssueRejectsIssueFromOtherWorkspace() async throws {
        var otherWs = Workspace(name: "Other WS")
        try await database.dbWriter.write { db in try otherWs.insert(db) }
        var issue = hydra.Issue(workspaceId: otherWs.id!, title: "Other WS issue")
        try await database.dbWriter.write { db in try issue.insert(db) }

        let params = AnyCodableValue.dictionary([
            "id": .number(Double(issue.id!)),
            "workspaceId": .number(Double(workspaceId)),
        ])

        do {
            _ = try await handler.handle(method: "db.delete_issue", params: params)
            XCTFail("Expected error — should not delete other workspace's issue")
        } catch let error as ReverseRpcHandlerError {
            XCTAssertEqual(error, .notFound("Issue", issue.id!))
        }
    }

    func testUpdateEpicRejectsEpicFromOtherWorkspace() async throws {
        var otherWs = Workspace(name: "Other WS")
        try await database.dbWriter.write { db in try otherWs.insert(db) }
        var epic = Epic(workspaceId: otherWs.id!, title: "Other WS epic")
        try await database.dbWriter.write { db in try epic.insert(db) }

        let params = AnyCodableValue.dictionary([
            "id": .number(Double(epic.id!)),
            "workspaceId": .number(Double(workspaceId)),
            "title": .string("Hacked"),
        ])

        do {
            _ = try await handler.handle(method: "db.update_epic", params: params)
            XCTFail("Expected error — should not modify other workspace's epic")
        } catch let error as ReverseRpcHandlerError {
            XCTAssertEqual(error, .notFound("Epic", epic.id!))
        }
    }

    // MARK: - delete_epic

    func testDeleteEpicRemovesFromDatabase() async throws {
        var epic = Epic(workspaceId: workspaceId, title: "To delete")
        try await database.dbWriter.write { db in try epic.insert(db) }

        let params = AnyCodableValue.dictionary([
            "id": .number(Double(epic.id!)),
            "workspaceId": .number(Double(workspaceId)),
        ])

        let result = try await handler.handle(method: "db.delete_epic", params: params)

        if case .dictionary(let dict) = result {
            XCTAssertEqual(dict["deleted"], .bool(true))
        } else {
            XCTFail("Expected dictionary result")
        }

        let deleted = try await database.dbWriter.read { db in
            try Epic.fetchOne(db, id: epic.id!)
        }
        XCTAssertNil(deleted)
    }

    func testDeleteEpicReturnsErrorForInvalidId() async throws {
        let params = AnyCodableValue.dictionary([
            "id": .number(999),
            "workspaceId": .number(Double(workspaceId)),
        ])

        do {
            _ = try await handler.handle(method: "db.delete_epic", params: params)
            XCTFail("Expected error")
        } catch let error as ReverseRpcHandlerError {
            XCTAssertEqual(error, .notFound("Epic", 999))
        }
    }

    func testDeleteEpicRejectsEpicFromOtherWorkspace() async throws {
        var otherWs = Workspace(name: "Other WS")
        try await database.dbWriter.write { db in try otherWs.insert(db) }
        var epic = Epic(workspaceId: otherWs.id!, title: "Other WS epic")
        try await database.dbWriter.write { db in try epic.insert(db) }

        let params = AnyCodableValue.dictionary([
            "id": .number(Double(epic.id!)),
            "workspaceId": .number(Double(workspaceId)),
        ])

        do {
            _ = try await handler.handle(method: "db.delete_epic", params: params)
            XCTFail("Expected error — should not delete other workspace's epic")
        } catch let error as ReverseRpcHandlerError {
            XCTAssertEqual(error, .notFound("Epic", epic.id!))
        }
    }

    // MARK: - Deterministic ordering

    func testListIssuesReturnsDeterministicOrder() async throws {
        try await database.dbWriter.write { db in
            var i1 = hydra.Issue(workspaceId: workspaceId, title: "First")
            var i2 = hydra.Issue(workspaceId: workspaceId, title: "Second")
            var i3 = hydra.Issue(workspaceId: workspaceId, title: "Third")
            try i1.insert(db)
            try i2.insert(db)
            try i3.insert(db)
        }

        let params = AnyCodableValue.dictionary([
            "workspaceId": .number(Double(workspaceId)),
        ])

        let result = try await handler.handle(method: "db.list_issues", params: params)

        if case .array(let issues) = result {
            XCTAssertEqual(issues.count, 3)
            // Should be ordered by ID (insertion order)
            if case .dictionary(let first) = issues[0],
               case .dictionary(let last) = issues[2] {
                XCTAssertEqual(first["title"], .string("First"))
                XCTAssertEqual(last["title"], .string("Third"))
            }
        } else {
            XCTFail("Expected array result")
        }
    }

    func testListEpicsReturnsDeterministicOrder() async throws {
        try await database.dbWriter.write { db in
            var e1 = Epic(workspaceId: workspaceId, title: "Alpha")
            var e2 = Epic(workspaceId: workspaceId, title: "Beta")
            try e1.insert(db)
            try e2.insert(db)
        }

        let params = AnyCodableValue.dictionary([
            "workspaceId": .number(Double(workspaceId)),
        ])

        let result = try await handler.handle(method: "db.list_epics", params: params)

        if case .array(let epics) = result {
            XCTAssertEqual(epics.count, 2)
            if case .dictionary(let first) = epics[0] {
                XCTAssertEqual(first["title"], .string("Alpha"))
            }
        } else {
            XCTFail("Expected array result")
        }
    }

    // MARK: - Timestamps in serialized records

    func testCreateIssueIncludesTimestamps() async throws {
        let params = AnyCodableValue.dictionary([
            "workspaceId": .number(Double(workspaceId)),
            "title": .string("Timestamped"),
        ])

        let result = try await handler.handle(method: "db.create_issue", params: params)

        if case .dictionary(let dict) = result {
            XCTAssertNotNil(dict["createdAt"])
            XCTAssertNotNil(dict["updatedAt"])
        } else {
            XCTFail("Expected dictionary result")
        }
    }

    func testCreateEpicIncludesTimestamps() async throws {
        let params = AnyCodableValue.dictionary([
            "workspaceId": .number(Double(workspaceId)),
            "title": .string("Timestamped Epic"),
        ])

        let result = try await handler.handle(method: "db.create_epic", params: params)

        if case .dictionary(let dict) = result {
            XCTAssertNotNil(dict["createdAt"])
            XCTAssertNotNil(dict["updatedAt"])
        } else {
            XCTFail("Expected dictionary result")
        }
    }

    // MARK: - Unknown method

    func testUnknownMethodReturnsError() async throws {
        do {
            _ = try await handler.handle(method: "db.unknown", params: nil)
            XCTFail("Expected error")
        } catch let error as ReverseRpcHandlerError {
            XCTAssertEqual(error, .unknownMethod("db.unknown"))
        }
    }
}
