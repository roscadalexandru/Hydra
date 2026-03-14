import Foundation
import GRDB

struct Workspace: Identifiable, Codable, Equatable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "workspaces"

    var id: Int64?
    var name: String
    var description: String
    var defaultAutonomyMode: AutonomyMode
    var createdAt: Date
    var updatedAt: Date

    enum AutonomyMode: String, Codable, CaseIterable {
        case supervised
        case autonomous
        case chat
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let name = Column(CodingKeys.name)
        static let defaultAutonomyMode = Column(CodingKeys.defaultAutonomyMode)
        static let createdAt = Column(CodingKeys.createdAt)
        static let updatedAt = Column(CodingKeys.updatedAt)
    }

    init(
        id: Int64? = nil,
        name: String,
        description: String = "",
        defaultAutonomyMode: AutonomyMode = .supervised,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.defaultAutonomyMode = defaultAutonomyMode
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
