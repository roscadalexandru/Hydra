import XCTest
@testable import hydra

final class SidecarBridgeTests: XCTestCase {

    // MARK: - Initial State

    func testInitialState() {
        let bridge = makeBridge()
        XCTAssertEqual(bridge.status, .idle)
        XCTAssertNil(bridge.sessionId)
        XCTAssertNil(bridge.sdkSessionId)
    }

    // MARK: - Start Session

    func testStartSessionSetsStatusToStarting() async throws {
        let (bridge, _) = makeBridgeAndMock()
        let _ = bridge.startSession(prompt: "hi", workingDirectory: "/tmp")
        // sessionId and status are set synchronously before the Task runs
        XCTAssertNotNil(bridge.sessionId)
        XCTAssertEqual(bridge.status, .starting)
    }

    func testStartSessionSendsRpc() async throws {
        let (bridge, mock) = makeBridgeAndMock()
        let _ = bridge.startSession(prompt: "hi", workingDirectory: "/tmp")

        try await waitUntil { mock.sentMessages.contains { $0.method == "start_session" } }

        let sent = mock.sentMessages.first { $0.method == "start_session" }
        XCTAssertNotNil(sent)
    }

    func testStartSessionTransitionsToRunning() async throws {
        let (bridge, mock) = makeBridgeAndMock()
        let _ = bridge.startSession(prompt: "hi", workingDirectory: "/tmp")
        try await emitSuccessfulStart(bridge: bridge, mock: mock)

        XCTAssertEqual(bridge.status, .running)
        XCTAssertEqual(bridge.sdkSessionId, "sdk-test")
    }

    func testSessionCompleteTransitionsToIdle() async throws {
        let (bridge, mock) = makeBridgeAndMock()
        let _ = bridge.startSession(prompt: "hi", workingDirectory: "/tmp")
        let sessionId = bridge.sessionId!
        try await emitSuccessfulStart(bridge: bridge, mock: mock)

        mock.emit(.event(StreamNotification(
            sessionId: sessionId,
            event: .sessionComplete(durationMs: 100, costUsd: 0.01)
        )))

        try await waitUntil { bridge.status == .idle }
        XCTAssertNil(bridge.sessionId)
        XCTAssertNil(bridge.sdkSessionId)
    }

    func testSessionErrorTransitionsToError() async throws {
        let (bridge, mock) = makeBridgeAndMock()
        let _ = bridge.startSession(prompt: "hi", workingDirectory: "/tmp")
        let sessionId = bridge.sessionId!
        try await emitSuccessfulStart(bridge: bridge, mock: mock)

        mock.emit(.event(StreamNotification(
            sessionId: sessionId,
            event: .sessionError(error: "something broke")
        )))

        try await waitUntil {
            if case .error("something broke") = bridge.status { return true }
            return false
        }
    }

    // MARK: - Send Message

    func testSendMessageSendsRpc() async throws {
        let (bridge, mock) = makeBridgeAndMock()
        let _ = bridge.startSession(prompt: "hi", workingDirectory: "/tmp")
        try await emitSuccessfulStart(bridge: bridge, mock: mock)

        // Call sendMessage in background — it will await the RPC response
        let sendTask = Task {
            try await bridge.sendMessage("hello world")
        }

        // Wait for the send_message RPC to appear
        try await waitUntil { mock.sentMessages.contains { $0.method == "send_message" } }

        // Emit RPC response
        let rpcId = mock.sentMessages.first { $0.method == "send_message" }!.id
        mock.emit(.response(RpcResponse(id: rpcId, result: .null, error: nil)))

        // sendMessage should return successfully
        try await sendTask.value
    }

    func testSendMessageThrowsWithNoActiveSession() async {
        let bridge = makeBridge()

        do {
            try await bridge.sendMessage("hi")
            XCTFail("Expected error")
        } catch {
            XCTAssertTrue(error is SidecarBridgeError)
        }
    }

    // MARK: - Cancel

    func testCancelTransitionsToCancellingAndSendsRpc() async throws {
        let (bridge, mock) = makeBridgeAndMock()
        let _ = bridge.startSession(prompt: "hi", workingDirectory: "/tmp")
        let sessionId = bridge.sessionId!
        try await emitSuccessfulStart(bridge: bridge, mock: mock)

        // Call cancel in background
        let cancelTask = Task { await bridge.cancel() }

        try await waitUntil { bridge.status == .cancelling }

        // Wait for cancel_session RPC
        try await waitUntil { mock.sentMessages.contains { $0.method == "cancel_session" } }

        // Emit RPC response for cancel
        let rpcId = mock.sentMessages.first { $0.method == "cancel_session" }!.id
        mock.emit(.response(RpcResponse(id: rpcId, result: .null, error: nil)))

        await cancelTask.value

        // Emit session_error (sidecar sends this after cancel)
        mock.emit(.event(StreamNotification(
            sessionId: sessionId,
            event: .sessionError(error: "cancelled")
        )))

        // Should transition to idle (not error) because we were cancelling
        try await waitUntil { bridge.status == .idle }
    }

    // MARK: - Shutdown

    func testShutdownTerminatesAndResetsState() async throws {
        let (bridge, mock) = makeBridgeAndMock()
        let _ = bridge.startSession(prompt: "hi", workingDirectory: "/tmp")
        try await emitSuccessfulStart(bridge: bridge, mock: mock)

        bridge.shutdown()

        XCTAssertEqual(bridge.status, .idle)
        XCTAssertNil(bridge.sessionId)
        XCTAssertNil(bridge.sdkSessionId)
        XCTAssertEqual(mock.terminateCallCount, 1)
    }

    // MARK: - Guard Against Double Start

    func testStartSessionWhileActiveReturnsError() async throws {
        let (bridge, mock) = makeBridgeAndMock()
        let _ = bridge.startSession(prompt: "hi", workingDirectory: "/tmp")
        try await emitSuccessfulStart(bridge: bridge, mock: mock)

        // Try to start another session while running
        let stream = bridge.startSession(prompt: "second", workingDirectory: "/tmp")

        var gotError = false
        do {
            for try await _ in stream {
                XCTFail("Should not receive events")
            }
        } catch {
            gotError = true
            XCTAssertEqual(error as? SidecarBridgeError, .sessionAlreadyActive)
        }
        XCTAssertTrue(gotError)
    }

    // MARK: - Process Crash

    func testProcessCrashTransitionsToError() async throws {
        let (bridge, mock) = makeBridgeAndMock()
        let _ = bridge.startSession(prompt: "hi", workingDirectory: "/tmp")
        try await emitSuccessfulStart(bridge: bridge, mock: mock)

        // Simulate unexpected process exit
        mock.simulateCrash()

        try await waitUntil {
            if case .error = bridge.status { return true }
            return false
        }
    }

    // MARK: - Event Delivery

    func testStreamDeliversAgentEvents() async throws {
        let (bridge, mock) = makeBridgeAndMock()
        let stream = bridge.startSession(prompt: "hi", workingDirectory: "/tmp")
        let sessionId = bridge.sessionId!

        // Collect events in background with timeout
        let eventsTask = Task { () -> [AgentEvent] in
            var collected: [AgentEvent] = []
            for try await event in stream {
                collected.append(event)
            }
            return collected
        }

        try await emitSuccessfulStart(bridge: bridge, mock: mock)

        // Emit some agent events
        mock.emit(.event(StreamNotification(
            sessionId: sessionId,
            event: .textDelta(delta: "Hello ")
        )))
        mock.emit(.event(StreamNotification(
            sessionId: sessionId,
            event: .textDelta(delta: "world")
        )))
        mock.emit(.event(StreamNotification(
            sessionId: sessionId,
            event: .assistantMessage(content: "Hello world")
        )))

        // Complete the session
        mock.emit(.event(StreamNotification(
            sessionId: sessionId,
            event: .sessionComplete(durationMs: 500, costUsd: 0.05)
        )))

        let events = try await eventsTask.value

        // sessionStarted + 2 textDelta + assistantMessage + sessionComplete = 5
        XCTAssertEqual(events.count, 5)
        XCTAssertEqual(events[0], .sessionStarted(sdkSessionId: "sdk-test"))
        XCTAssertEqual(events[1], .textDelta(delta: "Hello "))
        XCTAssertEqual(events[2], .textDelta(delta: "world"))
        XCTAssertEqual(events[3], .assistantMessage(content: "Hello world"))
        XCTAssertEqual(events[4], .sessionComplete(durationMs: 500, costUsd: 0.05))
    }

    // MARK: - Helpers

    private func makeBridge() -> SidecarBridge {
        let (bridge, _) = makeBridgeAndMock()
        return bridge
    }

    private func makeBridgeAndMock() -> (SidecarBridge, MockSidecarProcess) {
        let mock = MockSidecarProcess()
        let bridge = SidecarBridge(processFactory: { mock })
        return (bridge, mock)
    }

    /// Emits the RPC response for start_session and a sessionStarted event,
    /// then waits for status to become .running.
    private func emitSuccessfulStart(
        bridge: SidecarBridge,
        mock: MockSidecarProcess
    ) async throws {
        let sessionId = bridge.sessionId!

        // Wait for start_session RPC
        try await waitUntil { mock.sentMessages.contains { $0.method == "start_session" } }

        // Emit RPC response
        let rpcId = mock.sentMessages.first { $0.method == "start_session" }!.id
        mock.emit(.response(RpcResponse(id: rpcId, result: .null, error: nil)))

        // Emit sessionStarted
        mock.emit(.event(StreamNotification(
            sessionId: sessionId,
            event: .sessionStarted(sdkSessionId: "sdk-test")
        )))

        try await waitUntil { bridge.status == .running }
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        condition: @escaping () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                XCTFail("Timed out waiting for condition")
                throw SidecarBridgeTestError.timeout
            }
            try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }
    }
}

private enum SidecarBridgeTestError: Error {
    case timeout
}

// MARK: - Mock

private final class MockSidecarProcess: SidecarProcessProtocol, @unchecked Sendable {

    let events: AsyncStream<SidecarMessage>
    private let continuation: AsyncStream<SidecarMessage>.Continuation
    private let lock = NSLock()

    private var _isRunning = false
    private var _startCallCount = 0
    private var _terminateCallCount = 0
    private var _sentMessages: [(method: String, id: Int)] = []
    private var nextId = 1

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isRunning
    }

    var startCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _startCallCount
    }

    var terminateCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _terminateCallCount
    }

    var sentMessages: [(method: String, id: Int)] {
        lock.lock()
        defer { lock.unlock() }
        return _sentMessages
    }

    init() {
        let (stream, cont) = AsyncStream<SidecarMessage>.makeStream()
        self.events = stream
        self.continuation = cont
    }

    func start() throws {
        lock.lock()
        defer { lock.unlock() }
        _startCallCount += 1
        _isRunning = true
    }

    @discardableResult
    func send<P: Encodable>(method: String, params: P) throws -> Int {
        lock.lock()
        defer { lock.unlock() }
        guard _isRunning else { throw SidecarProcessError.notRunning }
        let id = nextId
        nextId += 1
        _sentMessages.append((method: method, id: id))
        return id
    }

    func terminate() {
        lock.lock()
        _terminateCallCount += 1
        _isRunning = false
        lock.unlock()
        continuation.finish()
    }

    // MARK: - Test Helpers

    func emit(_ message: SidecarMessage) {
        continuation.yield(message)
    }

    func simulateCrash() {
        lock.lock()
        _isRunning = false
        lock.unlock()
        continuation.finish()
    }
}
