import Foundation
import GRDB

struct ChatSession: Identifiable, Codable, Equatable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "chat_sessions"

    var id: Int64?
    var workspaceId: Int64
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
        static let issueId = Column(CodingKeys.issueId)
        static let status = Column(CodingKeys.status)
        static let createdAt = Column(CodingKeys.createdAt)
        static let updatedAt = Column(CodingKeys.updatedAt)
    }

    init(
        id: Int64? = nil,
        workspaceId: Int64,
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
        self.issueId = issueId
        self.sdkSessionId = sdkSessionId
        self.status = status
        self.title = title
        self.totalCostUsd = totalCostUsd
        self.totalDurationMs = totalDurationMs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
