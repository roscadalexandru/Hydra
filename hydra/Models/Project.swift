import Foundation
import GRDB

struct Project: Identifiable, Codable, Equatable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "projects"

    var id: Int64?
    var workspaceId: Int64
    var name: String
    var path: String
    var createdAt: Date

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let workspaceId = Column(CodingKeys.workspaceId)
        static let name = Column(CodingKeys.name)
        static let path = Column(CodingKeys.path)
    }

    init(
        id: Int64? = nil,
        workspaceId: Int64,
        name: String,
        path: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.workspaceId = workspaceId
        self.name = name
        self.path = path
        self.createdAt = createdAt
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
