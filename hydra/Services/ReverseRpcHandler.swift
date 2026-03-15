import Foundation
import GRDB

enum ReverseRpcHandlerError: Error, Equatable {
    case unknownMethod(String)
    case missingRequiredField(String)
    case notFound(String, Int64)
    case invalidFieldValue(String, String)
}

struct ReverseRpcHandler {
    let database: AppDatabase

    func handle(method: String, params: AnyCodableValue?) async throws -> AnyCodableValue {
        switch method {
        case "db.create_issue":
            return try await createIssue(params: params)
        case "db.get_issue":
            return try await getIssue(params: params)
        case "db.list_issues":
            return try await listIssues(params: params)
        case "db.update_issue":
            return try await updateIssue(params: params)
        case "db.delete_issue":
            return try await deleteIssue(params: params)
        case "db.list_epics":
            return try await listEpics(params: params)
        case "db.create_epic":
            return try await createEpic(params: params)
        case "db.update_epic":
            return try await updateEpic(params: params)
        case "db.delete_epic":
            return try await deleteEpic(params: params)
        default:
            throw ReverseRpcHandlerError.unknownMethod(method)
        }
    }

    // MARK: - Issues

    private func createIssue(params: AnyCodableValue?) async throws -> AnyCodableValue {
        let dict = try requireDict(params)
        let workspaceId = try requireInt64(dict, "workspaceId")
        let title = try requireString(dict, "title")

        var issue = Issue(
            workspaceId: workspaceId,
            epicId: optionalInt64(dict, "epicId"),
            title: title,
            description: optionalString(dict, "description") ?? "",
            status: optionalEnum(dict, "status") ?? .backlog,
            priority: optionalEnum(dict, "priority") ?? .medium,
            assigneeType: optionalString(dict, "assigneeType") ?? "human",
            assigneeName: optionalString(dict, "assigneeName") ?? ""
        )

        try await database.dbWriter.write { db in
            try issue.insert(db)
        }

        return issueToValue(issue)
    }

    private func getIssue(params: AnyCodableValue?) async throws -> AnyCodableValue {
        let dict = try requireDict(params)
        let id = try requireInt64(dict, "id")
        let workspaceId = try requireInt64(dict, "workspaceId")

        let issue = try await database.dbWriter.read { db in
            try Issue
                .filter(Issue.Columns.id == id && Issue.Columns.workspaceId == workspaceId)
                .fetchOne(db)
        }

        guard let issue else {
            throw ReverseRpcHandlerError.notFound("Issue", id)
        }

        return issueToValue(issue)
    }

    private func listIssues(params: AnyCodableValue?) async throws -> AnyCodableValue {
        let dict = try requireDict(params)
        let workspaceId = try requireInt64(dict, "workspaceId")

        let status = optionalString(dict, "status")
        let epicId = optionalInt64(dict, "epicId")
        let priority = optionalString(dict, "priority")
        let assigneeType = optionalString(dict, "assigneeType")

        let issues = try await database.dbWriter.read { db in
            var request = Issue.filter(Issue.Columns.workspaceId == workspaceId)

            if let status {
                request = request.filter(Issue.Columns.status == status)
            }
            if let epicId {
                request = request.filter(Issue.Columns.epicId == epicId)
            }
            if let priority {
                request = request.filter(Issue.Columns.priority == priority)
            }
            if let assigneeType {
                request = request.filter(Issue.Columns.assigneeType == assigneeType)
            }

            return try request.order(Issue.Columns.id).fetchAll(db)
        }

        return .array(issues.map { issueToValue($0) })
    }

    private func updateIssue(params: AnyCodableValue?) async throws -> AnyCodableValue {
        let dict = try requireDict(params)
        let id = try requireInt64(dict, "id")
        let workspaceId = try requireInt64(dict, "workspaceId")

        let updated = try await database.dbWriter.write { db -> Issue? in
            guard var issue = try Issue
                .filter(Issue.Columns.id == id && Issue.Columns.workspaceId == workspaceId)
                .fetchOne(db) else {
                return nil
            }

            if let title = optionalString(dict, "title") { issue.title = title }
            if let description = optionalString(dict, "description") { issue.description = description }
            if let status: Issue.Status = optionalEnum(dict, "status") { issue.status = status }
            if let priority: Issue.Priority = optionalEnum(dict, "priority") { issue.priority = priority }
            if let assigneeType = optionalString(dict, "assigneeType") { issue.assigneeType = assigneeType }
            if let assigneeName = optionalString(dict, "assigneeName") { issue.assigneeName = assigneeName }
            if dict["epicId"] != nil { issue.epicId = optionalInt64(dict, "epicId") }

            issue.updatedAt = Date()
            try issue.update(db)
            return issue
        }

        guard let updated else {
            throw ReverseRpcHandlerError.notFound("Issue", id)
        }

        return issueToValue(updated)
    }

    private func deleteIssue(params: AnyCodableValue?) async throws -> AnyCodableValue {
        let dict = try requireDict(params)
        let id = try requireInt64(dict, "id")
        let workspaceId = try requireInt64(dict, "workspaceId")

        let deleted = try await database.dbWriter.write { db -> Bool in
            guard let issue = try Issue
                .filter(Issue.Columns.id == id && Issue.Columns.workspaceId == workspaceId)
                .fetchOne(db) else {
                return false
            }
            try issue.delete(db)
            return true
        }

        guard deleted else {
            throw ReverseRpcHandlerError.notFound("Issue", id)
        }

        return .dictionary(["deleted": .bool(true), "id": .number(Double(id))])
    }

    // MARK: - Epics

    private func listEpics(params: AnyCodableValue?) async throws -> AnyCodableValue {
        let dict = try requireDict(params)
        let workspaceId = try requireInt64(dict, "workspaceId")

        let epics = try await database.dbWriter.read { db in
            try Epic.filter(Epic.Columns.workspaceId == workspaceId).order(Epic.Columns.id).fetchAll(db)
        }

        return .array(epics.map { epicToValue($0) })
    }

    private func createEpic(params: AnyCodableValue?) async throws -> AnyCodableValue {
        let dict = try requireDict(params)
        let workspaceId = try requireInt64(dict, "workspaceId")
        let title = try requireString(dict, "title")

        var epic = Epic(
            workspaceId: workspaceId,
            title: title,
            description: optionalString(dict, "description") ?? ""
        )

        try await database.dbWriter.write { db in
            try epic.insert(db)
        }

        return epicToValue(epic)
    }

    private func updateEpic(params: AnyCodableValue?) async throws -> AnyCodableValue {
        let dict = try requireDict(params)
        let id = try requireInt64(dict, "id")
        let workspaceId = try requireInt64(dict, "workspaceId")

        let updated = try await database.dbWriter.write { db -> Epic? in
            guard var epic = try Epic
                .filter(Epic.Columns.id == id && Epic.Columns.workspaceId == workspaceId)
                .fetchOne(db) else {
                return nil
            }

            if let title = optionalString(dict, "title") { epic.title = title }
            if let description = optionalString(dict, "description") { epic.description = description }

            epic.updatedAt = Date()
            try epic.update(db)
            return epic
        }

        guard let updated else {
            throw ReverseRpcHandlerError.notFound("Epic", id)
        }

        return epicToValue(updated)
    }

    private func deleteEpic(params: AnyCodableValue?) async throws -> AnyCodableValue {
        let dict = try requireDict(params)
        let id = try requireInt64(dict, "id")
        let workspaceId = try requireInt64(dict, "workspaceId")

        let deleted = try await database.dbWriter.write { db -> Bool in
            guard let epic = try Epic
                .filter(Epic.Columns.id == id && Epic.Columns.workspaceId == workspaceId)
                .fetchOne(db) else {
                return false
            }
            try epic.delete(db)
            return true
        }

        guard deleted else {
            throw ReverseRpcHandlerError.notFound("Epic", id)
        }

        return .dictionary(["deleted": .bool(true), "id": .number(Double(id))])
    }

    // MARK: - Serialization helpers

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private func issueToValue(_ issue: Issue) -> AnyCodableValue {
        var dict: [String: AnyCodableValue] = [
            "id": .number(Double(issue.id ?? 0)),
            "workspaceId": .number(Double(issue.workspaceId)),
            "title": .string(issue.title),
            "description": .string(issue.description),
            "status": .string(issue.status.rawValue),
            "priority": .string(issue.priority.rawValue),
            "assigneeType": .string(issue.assigneeType),
            "assigneeName": .string(issue.assigneeName),
            "createdAt": .string(Self.isoFormatter.string(from: issue.createdAt)),
            "updatedAt": .string(Self.isoFormatter.string(from: issue.updatedAt)),
        ]
        if let epicId = issue.epicId {
            dict["epicId"] = .number(Double(epicId))
        }
        return .dictionary(dict)
    }

    private func epicToValue(_ epic: Epic) -> AnyCodableValue {
        .dictionary([
            "id": .number(Double(epic.id ?? 0)),
            "workspaceId": .number(Double(epic.workspaceId)),
            "title": .string(epic.title),
            "description": .string(epic.description),
            "createdAt": .string(Self.isoFormatter.string(from: epic.createdAt)),
            "updatedAt": .string(Self.isoFormatter.string(from: epic.updatedAt)),
        ])
    }

    // MARK: - Param extraction helpers

    private func requireDict(_ params: AnyCodableValue?) throws -> [String: AnyCodableValue] {
        guard case .dictionary(let dict) = params else {
            throw ReverseRpcHandlerError.missingRequiredField("params")
        }
        return dict
    }

    private func requireString(_ dict: [String: AnyCodableValue], _ key: String) throws -> String {
        guard case .string(let val) = dict[key] else {
            throw ReverseRpcHandlerError.missingRequiredField(key)
        }
        return val
    }

    private func requireInt64(_ dict: [String: AnyCodableValue], _ key: String) throws -> Int64 {
        guard case .number(let val) = dict[key] else {
            throw ReverseRpcHandlerError.missingRequiredField(key)
        }
        return Int64(val)
    }

    private func optionalString(_ dict: [String: AnyCodableValue], _ key: String) -> String? {
        guard case .string(let val) = dict[key] else { return nil }
        return val
    }

    private func optionalInt64(_ dict: [String: AnyCodableValue], _ key: String) -> Int64? {
        guard case .number(let val) = dict[key] else { return nil }
        return Int64(val)
    }

    private func optionalEnum<E: RawRepresentable>(_ dict: [String: AnyCodableValue], _ key: String) -> E? where E.RawValue == String {
        guard case .string(let val) = dict[key] else { return nil }
        return E(rawValue: val)
    }
}
