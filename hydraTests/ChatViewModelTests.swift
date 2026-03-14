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
