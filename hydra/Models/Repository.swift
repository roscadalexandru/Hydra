import Foundation
import GRDB

struct Repository: Identifiable, Codable, Equatable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "repositories"

    var id: Int64?
    var projectId: Int64
    var name: String
    var path: String
    var createdAt: Date

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let projectId = Column(CodingKeys.projectId)
        static let name = Column(CodingKeys.name)
        static let path = Column(CodingKeys.path)
    }

    init(
        id: Int64? = nil,
        projectId: Int64,
        name: String,
        path: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.projectId = projectId
        self.name = name
        self.path = path
        self.createdAt = createdAt
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
