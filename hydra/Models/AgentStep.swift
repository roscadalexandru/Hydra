import Foundation
import GRDB

struct AgentStep: Identifiable, Codable, Equatable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "agent_steps"

    var id: Int64?
    var agentRunId: Int64
    var orderIndex: Int
    var description: String
    var status: Status
    var output: String?
    var filesChanged: String?
    var startedAt: Date?
    var finishedAt: Date?

    enum Status: String, Codable {
        case pending
        case running
        case completed
        case failed
        case skipped
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let agentRunId = Column(CodingKeys.agentRunId)
        static let orderIndex = Column(CodingKeys.orderIndex)
        static let status = Column(CodingKeys.status)
    }

    init(
        id: Int64? = nil,
        agentRunId: Int64,
        orderIndex: Int,
        description: String,
        status: Status = .pending,
        output: String? = nil,
        filesChanged: String? = nil,
        startedAt: Date? = nil,
        finishedAt: Date? = nil
    ) {
        self.id = id
        self.agentRunId = agentRunId
        self.orderIndex = orderIndex
        self.description = description
        self.status = status
        self.output = output
        self.filesChanged = filesChanged
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
