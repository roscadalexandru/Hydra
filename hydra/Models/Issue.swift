import Foundation
import GRDB

struct Issue: Identifiable, Codable, Equatable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "issues"

    var id: Int64?
    var workspaceId: Int64
    var epicId: Int64?
    var title: String
    var description: String
    var status: Status
    var priority: Priority
    var assigneeType: String
    var assigneeName: String
    var autonomyMode: String?
    var createdAt: Date
    var updatedAt: Date

    enum Status: String, Codable, CaseIterable {
        case backlog
        case inProgress = "in_progress"
        case inReview = "in_review"
        case done
    }

    enum Priority: String, Codable, CaseIterable {
        case urgent
        case high
        case medium
        case low
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let workspaceId = Column(CodingKeys.workspaceId)
        static let epicId = Column(CodingKeys.epicId)
        static let title = Column(CodingKeys.title)
        static let status = Column(CodingKeys.status)
        static let priority = Column(CodingKeys.priority)
        static let assigneeType = Column(CodingKeys.assigneeType)
    }

    var isAgentAssigned: Bool { assigneeType == "agent" }

    init(
        id: Int64? = nil,
        workspaceId: Int64,
        epicId: Int64? = nil,
        title: String,
        description: String = "",
        status: Status = .backlog,
        priority: Priority = .medium,
        assigneeType: String = "human",
        assigneeName: String = "",
        autonomyMode: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.workspaceId = workspaceId
        self.epicId = epicId
        self.title = title
        self.description = description
        self.status = status
        self.priority = priority
        self.assigneeType = assigneeType
        self.assigneeName = assigneeName
        self.autonomyMode = autonomyMode
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
