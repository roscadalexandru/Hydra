import Foundation
import GRDB

struct Epic: Identifiable, Codable, Equatable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "epics"

    var id: Int64?
    var projectId: Int64
    var title: String
    var description: String
    var createdAt: Date
    var updatedAt: Date

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let projectId = Column(CodingKeys.projectId)
        static let title = Column(CodingKeys.title)
    }

    init(
        id: Int64? = nil,
        projectId: Int64,
        title: String,
        description: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.projectId = projectId
        self.title = title
        self.description = description
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
