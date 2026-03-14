import XCTest
import GRDB
@testable import hydra

final class ChatMessageTests: XCTestCase {

    private func makeSessionAndDB() throws -> (AppDatabase, ChatSession) {
        let db = try TestDatabase.make()
        var workspace = Workspace(name: "Test")
        try db.dbWriter.write { dbConn in
            try workspace.insert(dbConn)
        }
        var session = ChatSession(workspaceId: workspace.id!)
        try db.dbWriter.write { dbConn in
            try session.insert(dbConn)
        }
        return (db, session)
    }

    func testCreateChatMessage() throws {
        let (db, session) = try makeSessionAndDB()
        try db.dbWriter.write { dbConn in
            var message = ChatMessage(chatSessionId: session.id!, orderIndex: 0, role: .user, content: "Hello")
            try message.insert(dbConn)

            XCTAssertNotNil(message.id)
            XCTAssertEqual(message.role, .user)
            XCTAssertEqual(message.content, "Hello")
            XCTAssertEqual(message.isError, false)
        }
    }

    func testChatMessageDefaults() throws {
        let message = ChatMessage(chatSessionId: 1, orderIndex: 0, role: .assistant)
        XCTAssertNil(message.id)
        XCTAssertEqual(message.content, "")
        XCTAssertEqual(message.isError, false)
        XCTAssertNil(message.toolName)
        XCTAssertNil(message.toolId)
        XCTAssertNil(message.toolInput)
    }

    func testMessageRoles() throws {
        let (db, session) = try makeSessionAndDB()
        try db.dbWriter.write { dbConn in
            var msg1 = ChatMessage(chatSessionId: session.id!, orderIndex: 0, role: .user, content: "Hi")
            var msg2 = ChatMessage(chatSessionId: session.id!, orderIndex: 1, role: .assistant, content: "Hello!")
            var msg3 = ChatMessage(chatSessionId: session.id!, orderIndex: 2, role: .toolUse, content: "read_file")
            var msg4 = ChatMessage(chatSessionId: session.id!, orderIndex: 3, role: .toolResult, content: "file contents")
            try msg1.insert(dbConn)
            try msg2.insert(dbConn)
            try msg3.insert(dbConn)
            try msg4.insert(dbConn)

            let messages = try ChatMessage
                .filter(ChatMessage.Columns.chatSessionId == session.id!)
                .order(ChatMessage.Columns.orderIndex.asc)
                .fetchAll(dbConn)

            XCTAssertEqual(messages.count, 4)
            XCTAssertEqual(messages[0].role, .user)
            XCTAssertEqual(messages[1].role, .assistant)
            XCTAssertEqual(messages[2].role, .toolUse)
            XCTAssertEqual(messages[3].role, .toolResult)
        }
    }

    func testMessageOrdering() throws {
        let (db, session) = try makeSessionAndDB()
        try db.dbWriter.write { dbConn in
            var msg3 = ChatMessage(chatSessionId: session.id!, orderIndex: 2, role: .assistant, content: "Third")
            var msg1 = ChatMessage(chatSessionId: session.id!, orderIndex: 0, role: .user, content: "First")
            var msg2 = ChatMessage(chatSessionId: session.id!, orderIndex: 1, role: .assistant, content: "Second")
            try msg3.insert(dbConn)
            try msg1.insert(dbConn)
            try msg2.insert(dbConn)

            let messages = try ChatMessage
                .filter(ChatMessage.Columns.chatSessionId == session.id!)
                .order(ChatMessage.Columns.orderIndex.asc)
                .fetchAll(dbConn)

            XCTAssertEqual(messages.count, 3)
            XCTAssertEqual(messages[0].content, "First")
            XCTAssertEqual(messages[1].content, "Second")
            XCTAssertEqual(messages[2].content, "Third")
        }
    }

    func testToolUseFields() throws {
        let (db, session) = try makeSessionAndDB()
        try db.dbWriter.write { dbConn in
            var message = ChatMessage(
                chatSessionId: session.id!,
                orderIndex: 0,
                role: .toolUse,
                content: "read_file",
                toolName: "read_file",
                toolId: "tool-123",
                toolInput: "{\"path\": \"/tmp/test.txt\"}"
            )
            try message.insert(dbConn)

            let fetched = try ChatMessage.fetchOne(dbConn, key: message.id)
            XCTAssertEqual(fetched?.toolName, "read_file")
            XCTAssertEqual(fetched?.toolId, "tool-123")
            XCTAssertEqual(fetched?.toolInput, "{\"path\": \"/tmp/test.txt\"}")
        }
    }

    func testToolResultErrorFlag() throws {
        let (db, session) = try makeSessionAndDB()
        try db.dbWriter.write { dbConn in
            var message = ChatMessage(
                chatSessionId: session.id!,
                orderIndex: 0,
                role: .toolResult,
                content: "Error: file not found",
                toolId: "tool-456",
                isError: true
            )
            try message.insert(dbConn)

            let fetched = try ChatMessage.fetchOne(dbConn, key: message.id)
            XCTAssertEqual(fetched?.isError, true)
            XCTAssertEqual(fetched?.toolId, "tool-456")
        }
    }

    func testCascadeDeleteWithSession() throws {
        let (db, session) = try makeSessionAndDB()
        try db.dbWriter.write { dbConn in
            var message = ChatMessage(chatSessionId: session.id!, orderIndex: 0, role: .user, content: "Test")
            try message.insert(dbConn)
            let messageId = message.id

            _ = try ChatSession.deleteAll(dbConn)

            let fetched = try ChatMessage.fetchOne(dbConn, key: messageId)
            XCTAssertNil(fetched)
        }
    }

    func testCascadeDeleteWithWorkspace() throws {
        let db = try TestDatabase.make()
        var workspace = Workspace(name: "Test")
        try db.dbWriter.write { dbConn in
            try workspace.insert(dbConn)
        }
        var session = ChatSession(workspaceId: workspace.id!)
        try db.dbWriter.write { dbConn in
            try session.insert(dbConn)
        }
        try db.dbWriter.write { dbConn in
            var message = ChatMessage(chatSessionId: session.id!, orderIndex: 0, role: .user, content: "Test")
            try message.insert(dbConn)
            let messageId = message.id

            _ = try Workspace.deleteAll(dbConn)

            let fetched = try ChatMessage.fetchOne(dbConn, key: messageId)
            XCTAssertNil(fetched)
        }
    }
}
