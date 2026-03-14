import Foundation
import GRDB

struct ChatMessage: Identifiable, Codable, Equatable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "chat_messages"

    var id: Int64?
    var chatSessionId: Int64
    var orderIndex: Int
    var role: Role
    var content: String
    var toolName: String?
    var toolId: String?
    var toolInput: String?
    var isError: Bool
    var createdAt: Date

    enum Role: String, Codable {
        case user
        case assistant
        case toolUse
        case toolResult
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let chatSessionId = Column(CodingKeys.chatSessionId)
        static let orderIndex = Column(CodingKeys.orderIndex)
        static let role = Column(CodingKeys.role)
        static let createdAt = Column(CodingKeys.createdAt)
    }

    init(
        id: Int64? = nil,
        chatSessionId: Int64,
        orderIndex: Int,
        role: Role,
        content: String = "",
        toolName: String? = nil,
        toolId: String? = nil,
        toolInput: String? = nil,
        isError: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.chatSessionId = chatSessionId
        self.orderIndex = orderIndex
        self.role = role
        self.content = content
        self.toolName = toolName
        self.toolId = toolId
        self.toolInput = toolInput
        self.isError = isError
        self.createdAt = createdAt
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
