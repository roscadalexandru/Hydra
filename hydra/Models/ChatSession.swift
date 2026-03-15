import Foundation
import GRDB

struct ChatSession: Identifiable, Codable, Equatable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "chat_sessions"

    var id: Int64?
    var workspaceId: Int64
    var projectId: Int64?
    var issueId: Int64?
    var sdkSessionId: String?
    var status: Status
    var title: String
    var totalCostUsd: Double?
    var totalDurationMs: Int?
    var createdAt: Date
    var updatedAt: Date

    enum Status: String, Codable {
        case active
        case completed
        case failed
        case cancelled
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let workspaceId = Column(CodingKeys.workspaceId)
        static let projectId = Column(CodingKeys.projectId)
        static let issueId = Column(CodingKeys.issueId)
        static let status = Column(CodingKeys.status)
        static let createdAt = Column(CodingKeys.createdAt)
        static let updatedAt = Column(CodingKeys.updatedAt)
    }

    init(
        id: Int64? = nil,
        workspaceId: Int64,
        projectId: Int64? = nil,
        issueId: Int64? = nil,
        sdkSessionId: String? = nil,
        status: Status = .active,
        title: String = "New Chat",
        totalCostUsd: Double? = nil,
        totalDurationMs: Int? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.workspaceId = workspaceId
        self.projectId = projectId
        self.issueId = issueId
        self.sdkSessionId = sdkSessionId
        self.status = status
        self.title = title
        self.totalCostUsd = totalCostUsd
        self.totalDurationMs = totalDurationMs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - Queries

    static func fetchAllForWorkspace(_ db: Database, workspaceId: Int64) throws -> [ChatSession] {
        try ChatSession
            .filter(Columns.workspaceId == workspaceId)
            .order(Columns.updatedAt.desc)
            .fetchAll(db)
    }

    // MARK: - Title Generation

    static func generateTitle(from message: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 50 {
            return trimmed
        }
        return String(trimmed.prefix(50)) + "..."
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
