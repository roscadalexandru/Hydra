import Foundation
import GRDB

struct AgentRun: Identifiable, Codable, Equatable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "agent_runs"

    var id: Int64?
    var issueId: Int64
    var status: Status
    var startedAt: Date
    var finishedAt: Date?
    var error: String?

    enum Status: String, Codable {
        case running
        case completed
        case failed
        case cancelled
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let issueId = Column(CodingKeys.issueId)
        static let status = Column(CodingKeys.status)
    }

    init(
        id: Int64? = nil,
        issueId: Int64,
        status: Status = .running,
        startedAt: Date = Date(),
        finishedAt: Date? = nil,
        error: String? = nil
    ) {
        self.id = id
        self.issueId = issueId
        self.status = status
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.error = error
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
