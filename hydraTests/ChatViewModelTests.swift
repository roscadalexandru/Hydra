import XCTest
import Combine
import GRDB
@testable import hydra

@MainActor
final class ChatViewModelTests: XCTestCase {

    // MARK: - Send Creates User Message

    func testSendCreatesUserMessage() async throws {
        let (vm, _, db) = try makeViewModel()
        vm.inputText = "Hello agent"
        vm.send()

        try await waitUntil { vm.messages.contains { $0.role == .user } }

        let userMsg = vm.messages.first { $0.role == .user }
        XCTAssertEqual(userMsg?.content, "Hello agent")
        XCTAssertEqual(userMsg?.orderIndex, 0)

        // Verify persisted in DB
        try await db.dbWriter.read { dbConn in
            let persisted = try ChatMessage.filter(ChatMessage.Columns.role == ChatMessage.Role.user.rawValue).fetchAll(dbConn)
            XCTAssertEqual(persisted.count, 1)
            XCTAssertEqual(persisted[0].content, "Hello agent")
        }
    }

    func testSendClearsInputText() async throws {
        let (vm, _, _) = try makeViewModel()
        vm.inputText = "Hello"
        vm.send()
        XCTAssertEqual(vm.inputText, "")
    }

    func testSendIgnoresEmptyInput() async throws {
        let (vm, mock, _) = try makeViewModel()
        vm.inputText = "   "
        vm.send()
        XCTAssertFalse(mock.startSessionCalled)
    }

    // MARK: - Streaming

    func testTextDeltaAccumulates() async throws {
        let (vm, mock, _) = try makeViewModel()
        vm.inputText = "Hi"
        vm.send()

        try await waitUntil { mock.startSessionCalled }
        mock.emit(.textDelta(delta: "Hello "))
        try await waitUntil { vm.streamingText == "Hello " }

        mock.emit(.textDelta(delta: "world"))
        try await waitUntil { vm.streamingText == "Hello world" }
    }

    func testAssistantMessagePersisted() async throws {
        let (vm, mock, db) = try makeViewModel()
        vm.inputText = "Hi"
        vm.send()

        try await waitUntil { mock.startSessionCalled }
        mock.emit(.textDelta(delta: "Hello "))
        mock.emit(.assistantMessage(content: "Hello world"))

        try await waitUntil { vm.messages.contains { $0.role == .assistant } }

        let assistantMsg = vm.messages.first { $0.role == .assistant }
        XCTAssertEqual(assistantMsg?.content, "Hello world")

        // streamingText should be cleared
        XCTAssertEqual(vm.streamingText, "")

        // Verify persisted
        try await db.dbWriter.read { dbConn in
            let persisted = try ChatMessage.filter(ChatMessage.Columns.role == ChatMessage.Role.assistant.rawValue).fetchAll(dbConn)
            XCTAssertEqual(persisted.count, 1)
            XCTAssertEqual(persisted[0].content, "Hello world")
        }
    }

    // MARK: - Tool Events

    func testToolUseCreatesChatMessage() async throws {
        let (vm, mock, _) = try makeViewModel()
        vm.inputText = "Read a file"
        vm.send()

        try await waitUntil { mock.startSessionCalled }
        mock.emit(.toolUse(toolName: "read_file", toolId: "tool-1", input: .string("/tmp/test.txt")))

        try await waitUntil { vm.messages.contains { $0.role == .toolUse } }

        let toolMsg = vm.messages.first { $0.role == .toolUse }
        XCTAssertEqual(toolMsg?.toolName, "read_file")
        XCTAssertEqual(toolMsg?.toolId, "tool-1")
        XCTAssertNotNil(toolMsg?.toolInput)
    }

    func testToolResultCreatesChatMessage() async throws {
        let (vm, mock, _) = try makeViewModel()
        vm.inputText = "Read a file"
        vm.send()

        try await waitUntil { mock.startSessionCalled }
        mock.emit(.toolResult(toolId: "tool-1", result: .string("file contents"), isError: false))

        try await waitUntil { vm.messages.contains { $0.role == .toolResult } }

        let resultMsg = vm.messages.first { $0.role == .toolResult }
        XCTAssertEqual(resultMsg?.toolId, "tool-1")
        XCTAssertEqual(resultMsg?.isError, false)
    }

    func testToolResultWithError() async throws {
        let (vm, mock, _) = try makeViewModel()
        vm.inputText = "Read a file"
        vm.send()

        try await waitUntil { mock.startSessionCalled }
        mock.emit(.toolResult(toolId: "tool-2", result: .string("not found"), isError: true))

        try await waitUntil { vm.messages.contains { $0.role == .toolResult } }

        let resultMsg = vm.messages.first { $0.role == .toolResult }
        XCTAssertEqual(resultMsg?.isError, true)
    }

    // MARK: - Session Lifecycle

    func testSessionStartedUpdatesSdkId() async throws {
        let (vm, mock, _) = try makeViewModel()
        vm.inputText = "Hi"
        vm.send()

        try await waitUntil { mock.startSessionCalled }
        mock.emit(.sessionStarted(sdkSessionId: "sdk-abc"))

        try await waitUntil { vm.session?.sdkSessionId == "sdk-abc" }
        XCTAssertEqual(vm.session?.sdkSessionId, "sdk-abc")
    }

    func testSessionCompleteUpdatesCost() async throws {
        let (vm, mock, _) = try makeViewModel()
        vm.inputText = "Hi"
        vm.send()

        try await waitUntil { mock.startSessionCalled }
        mock.emit(.sessionComplete(durationMs: 1500, costUsd: 0.05))
        mock.finish()

        try await waitUntil { vm.session?.status == .completed }

        XCTAssertEqual(vm.session?.totalDurationMs, 1500)
        XCTAssertEqual(vm.session?.totalCostUsd, 0.05)
        XCTAssertFalse(vm.isStreaming)
    }

    func testSessionErrorSetsStatus() async throws {
        let (vm, mock, _) = try makeViewModel()
        vm.inputText = "Hi"
        vm.send()

        try await waitUntil { mock.startSessionCalled }
        mock.emit(.sessionError(error: "something broke"))
        mock.finish()

        try await waitUntil { vm.session?.status == .failed }
        XCTAssertEqual(vm.errorMessage, "something broke")
        XCTAssertFalse(vm.isStreaming)
    }

    // MARK: - Session Loading

    func testLoadExistingSession() async throws {
        let (vm, _, db) = try makeViewModel()

        // Create a session with messages in the DB using the test workspace
        let session = try makeSessionWithMessages(
            db: db, workspaceId: testWorkspaceId, sdkSessionId: "sdk-prev", title: "Previous Chat",
            messages: [
                (role: .user, content: "Hello"),
                (role: .assistant, content: "Hi there!")
            ]
        )

        vm.loadSession(session)

        try await waitUntil { vm.messages.count == 2 }

        XCTAssertEqual(vm.session?.id, session.id)
        XCTAssertEqual(vm.session?.sdkSessionId, "sdk-prev")
        XCTAssertEqual(vm.messages.count, 2)
        XCTAssertEqual(vm.messages[0].role, .user)
        XCTAssertEqual(vm.messages[1].role, .assistant)
    }

    func testLoadExistingSessionSetsNextOrderIndex() async throws {
        let (vm, _, db) = try makeViewModel()

        let session = try makeSessionWithMessages(
            db: db, workspaceId: testWorkspaceId,
            messages: [
                (role: .user, content: "Hello"),
                (role: .assistant, content: "Hi")
            ]
        )

        vm.loadSession(session)
        try await waitUntil { vm.messages.count == 2 }

        // Send a new message — it should get orderIndex 2
        vm.inputText = "Follow up"
        vm.send()

        try await waitUntil { vm.messages.count == 3 }
        let newMsg = vm.messages.last { $0.role == .user && $0.content == "Follow up" }
        XCTAssertEqual(newMsg?.orderIndex, 2)
    }

    // MARK: - Session Resume

    func testSendInExistingSessionPassesResumeSessionId() async throws {
        let (vm, mock, db) = try makeViewModel()

        let session = try makeSessionWithMessages(
            db: db, workspaceId: testWorkspaceId, sdkSessionId: "sdk-to-resume",
            messages: []
        )

        vm.loadSession(session)

        vm.inputText = "Continue the conversation"
        vm.send()

        try await waitUntil { mock.startSessionCalled }
        XCTAssertEqual(mock.lastResumeSessionId, "sdk-to-resume")
    }

    func testSendInNewSessionHasNilResumeSessionId() async throws {
        let (vm, mock, _) = try makeViewModel()
        vm.inputText = "Hello"
        vm.send()

        try await waitUntil { mock.startSessionCalled }
        XCTAssertNil(mock.lastResumeSessionId)
    }

    // MARK: - Title Auto-generation

    func testFirstUserMessageUpdatesTitleFromDefault() async throws {
        let (vm, mock, db) = try makeViewModel()
        vm.inputText = "How do I set up CI/CD?"
        vm.send()

        try await waitUntil { mock.startSessionCalled }

        // Wait for async title update to persist
        try await waitUntil { vm.session?.title == "How do I set up CI/CD?" }

        XCTAssertEqual(vm.session?.title, "How do I set up CI/CD?")

        // Verify persisted
        let sessionId = vm.session?.id
        try await db.dbWriter.read { dbConn in
            let fetched = try ChatSession.fetchOne(dbConn, key: sessionId)
            XCTAssertEqual(fetched?.title, "How do I set up CI/CD?")
        }
    }

    func testSecondMessageDoesNotChangeTitle() async throws {
        let (vm, mock, _) = try makeViewModel()

        // First message
        vm.inputText = "First message"
        vm.send()
        try await waitUntil { mock.startSessionCalled }
        try await waitUntil { vm.session?.title == "First message" }

        mock.emit(.sessionComplete(durationMs: 100, costUsd: 0.01))
        mock.finish()
        try await waitUntil { !vm.isStreaming }

        // Reset mock for second send
        let (_, mock2) = resetMock(vm)
        vm.inputText = "Second message"
        vm.send()

        try await waitUntil { mock2.startSessionCalled }

        // Title should still be from first message
        XCTAssertEqual(vm.session?.title, "First message")
    }

    // MARK: - Cancel

    func testCancelCallsBridge() async throws {
        let (vm, mock, _) = try makeViewModel()
        vm.inputText = "Hi"
        vm.send()

        try await waitUntil { mock.startSessionCalled }
        vm.cancelSession()

        try await waitUntil { mock.cancelCalled }
        XCTAssertTrue(mock.cancelCalled)
    }

    // MARK: - Helpers

    private func makeViewModel() throws -> (ChatViewModel, MockChatBridge, AppDatabase) {
        let db = try TestDatabase.make()
        var workspace = Workspace(name: "Test")
        try db.dbWriter.write { dbConn in
            try workspace.insert(dbConn)
        }
        let mock = MockChatBridge()
        let vm = ChatViewModel(
            database: db,
            bridge: mock,
            workspaceId: workspace.id!,
            workingDirectory: "/tmp"
        )
        return (vm, mock, db)
    }

    private var testWorkspaceId: Int64 {
        // Extracted from makeViewModel — workspace ID is always 1 for first insert
        1
    }

    private func makeSessionWithMessages(
        db: AppDatabase,
        workspaceId: Int64,
        sdkSessionId: String? = nil,
        title: String = "New Chat",
        messages: [(role: ChatMessage.Role, content: String)]
    ) throws -> ChatSession {
        var session = ChatSession(workspaceId: workspaceId, sdkSessionId: sdkSessionId, title: title)
        try db.dbWriter.write { dbConn in
            try session.insert(dbConn)
            for (index, msg) in messages.enumerated() {
                var chatMsg = ChatMessage(chatSessionId: session.id!, orderIndex: index, role: msg.role, content: msg.content)
                try chatMsg.insert(dbConn)
            }
        }
        return session
    }

    private func resetMock(_ vm: ChatViewModel) -> (ChatViewModel, MockChatBridge) {
        let newMock = MockChatBridge()
        vm.replaceBridge(newMock)
        return (vm, newMock)
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        condition: @escaping () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                XCTFail("Timed out waiting for condition")
                throw ChatViewModelTestError.timeout
            }
            try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }
    }
}

private enum ChatViewModelTestError: Error {
    case timeout
}

// MARK: - Mock

@MainActor
private final class MockChatBridge: ChatBridgeProtocol {
    var status: SidecarBridge.SessionStatus = .idle
    private(set) var startSessionCalled = false
    private(set) var sendMessageCalled = false
    private(set) var cancelCalled = false
    private(set) var lastPrompt: String?
    private(set) var lastResumeSessionId: String?

    private var continuation: AsyncThrowingStream<AgentEvent, Error>.Continuation?

    func startSession(
        prompt: String,
        workingDirectory: String,
        systemPrompt: String?,
        permissionMode: PermissionMode,
        allowedTools: [String]?,
        resumeSessionId: String?
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        startSessionCalled = true
        lastPrompt = prompt
        lastResumeSessionId = resumeSessionId
        status = .running

        let (stream, cont) = AsyncThrowingStream<AgentEvent, Error>.makeStream()
        self.continuation = cont
        return stream
    }

    func sendMessage(_ message: String) async throws {
        sendMessageCalled = true
    }

    func cancel() async {
        cancelCalled = true
    }

    // Test helper
    func emit(_ event: AgentEvent) {
        continuation?.yield(event)
    }

    func finish() {
        continuation?.finish()
        continuation = nil
    }
}
