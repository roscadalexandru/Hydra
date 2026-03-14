import XCTest
@testable import hydra

final class SidecarProcessTests: XCTestCase {

    private var sidecarScript: String {
        let testFile = URL(fileURLWithPath: #file)
        let projectRoot = testFile.deletingLastPathComponent().deletingLastPathComponent()
        return projectRoot.appendingPathComponent("sidecar/src/index.js").path
    }

    private func skipIfSidecarUnavailable() throws {
        guard FileManager.default.fileExists(atPath: sidecarScript) else {
            throw XCTSkip("Sidecar script not found at \(sidecarScript)")
        }
        let nodePath = ["/opt/homebrew/bin/node", "/usr/local/bin/node"]
            .first { FileManager.default.fileExists(atPath: $0) }
        guard nodePath != nil else {
            throw XCTSkip("Node.js not found")
        }
    }

    // MARK: - Initial State

    func testInitialStateIsNotRunning() throws {
        try skipIfSidecarUnavailable()
        let process = SidecarProcess(sidecarScript: sidecarScript)
        XCTAssertFalse(process.isRunning)
    }

    // MARK: - Start

    func testStartMakesProcessRunning() throws {
        try skipIfSidecarUnavailable()
        let sidecar = SidecarProcess(sidecarScript: sidecarScript)
        try sidecar.start()
        XCTAssertTrue(sidecar.isRunning)
        sidecar.terminate()
    }

    func testStartTwiceThrows() throws {
        try skipIfSidecarUnavailable()
        let sidecar = SidecarProcess(sidecarScript: sidecarScript)
        try sidecar.start()
        XCTAssertThrowsError(try sidecar.start()) { error in
            XCTAssertTrue(error is SidecarProcessError)
        }
        sidecar.terminate()
    }

    // MARK: - Send

    func testSendReturnsIncrementingRequestIds() throws {
        try skipIfSidecarUnavailable()
        let sidecar = SidecarProcess(sidecarScript: sidecarScript)
        try sidecar.start()

        let id1 = try sidecar.send(method: "start_session", params: StartSessionParams(
            sessionId: "s1", prompt: "hi", workingDirectory: "/tmp",
            systemPrompt: nil, permissionMode: .default,
            allowedTools: nil, resumeSessionId: nil
        ))
        let id2 = try sidecar.send(method: "send_message", params: SendMessageParams(
            sessionId: "s1", message: "hello"
        ))

        XCTAssertEqual(id1, 1)
        XCTAssertEqual(id2, 2)

        sidecar.terminate()
    }

    // MARK: - Events

    func testEventsStreamYieldsResponseFromEchoSidecar() async throws {
        try skipIfSidecarUnavailable()
        let sidecar = SidecarProcess(sidecarScript: sidecarScript)
        try sidecar.start()

        let _ = try sidecar.send(method: "start_session", params: StartSessionParams(
            sessionId: "test-123", prompt: "hi", workingDirectory: "/tmp",
            systemPrompt: nil, permissionMode: .default,
            allowedTools: nil, resumeSessionId: nil
        ))

        let received = try await collectEvents(from: sidecar, count: 1, timeout: 5)

        XCTAssertEqual(received.count, 1)
        if case .response(let response) = received[0] {
            XCTAssertEqual(response.id, 1)
        } else {
            XCTFail("Expected response, got event")
        }

        sidecar.terminate()
    }

    func testMultipleCommandsYieldCorrespondingResponses() async throws {
        try skipIfSidecarUnavailable()
        let sidecar = SidecarProcess(sidecarScript: sidecarScript)
        try sidecar.start()

        let _ = try sidecar.send(method: "start_session", params: StartSessionParams(
            sessionId: "s1", prompt: "hi", workingDirectory: "/tmp",
            systemPrompt: nil, permissionMode: .default,
            allowedTools: nil, resumeSessionId: nil
        ))
        let _ = try sidecar.send(method: "send_message", params: SendMessageParams(
            sessionId: "s1", message: "hello"
        ))

        let received = try await collectEvents(from: sidecar, count: 2, timeout: 5)

        XCTAssertEqual(received.count, 2)
        if case .response(let r1) = received[0] {
            XCTAssertEqual(r1.id, 1)
        } else { XCTFail("Expected response at index 0") }
        if case .response(let r2) = received[1] {
            XCTAssertEqual(r2.id, 2)
        } else { XCTFail("Expected response at index 1") }

        sidecar.terminate()
    }

    // MARK: - Terminate

    func testTerminateMakesProcessNotRunning() throws {
        try skipIfSidecarUnavailable()
        let sidecar = SidecarProcess(sidecarScript: sidecarScript)
        try sidecar.start()
        XCTAssertTrue(sidecar.isRunning)

        sidecar.terminate()

        try waitUntil(timeout: 5) { !sidecar.isRunning }
        XCTAssertFalse(sidecar.isRunning)
    }

    func testTerminateOnNonStartedProcessIsNoOp() throws {
        try skipIfSidecarUnavailable()
        let sidecar = SidecarProcess(sidecarScript: sidecarScript)
        sidecar.terminate() // should not crash
        XCTAssertFalse(sidecar.isRunning)
    }

    // MARK: - IsRunning reflects actual process state

    func testIsRunningBecomesFalseAfterProcessExits() throws {
        try skipIfSidecarUnavailable()
        let sidecar = SidecarProcess(sidecarScript: sidecarScript)
        try sidecar.start()

        // Send shutdown command — echo sidecar exits on shutdown
        let _ = try sidecar.send(method: "shutdown", params: [String: String]())

        try waitUntil(timeout: 5) { !sidecar.isRunning }
        XCTAssertFalse(sidecar.isRunning)
    }

    // MARK: - Helpers

    private func collectEvents(
        from sidecar: SidecarProcess,
        count: Int,
        timeout seconds: UInt64
    ) async throws -> [SidecarMessage] {
        try await withThrowingTaskGroup(of: [SidecarMessage].self) { group in
            group.addTask {
                var received: [SidecarMessage] = []
                for await message in sidecar.events {
                    received.append(message)
                    if received.count >= count { break }
                }
                return received
            }
            group.addTask {
                try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                throw SidecarTestError.timeout
            }
            let result = try await group.next() ?? []
            group.cancelAll()
            return result
        }
    }

    private func waitUntil(timeout: TimeInterval, condition: @escaping () -> Bool) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                XCTFail("Timed out waiting for condition")
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
    }
}

private enum SidecarTestError: Error {
    case timeout
}
