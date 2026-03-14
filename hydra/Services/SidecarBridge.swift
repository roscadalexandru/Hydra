import AppKit
import Foundation

@Observable
@MainActor
final class SidecarBridge {

    private(set) var sessionId: String?
    private(set) var sdkSessionId: String?
    private(set) var status: SessionStatus = .idle

    enum SessionStatus: Equatable {
        case idle
        case starting
        case running
        case cancelling
        case error(String)
    }

    private let processFactory: @Sendable () -> any SidecarProcessProtocol

    // Accessed from deinit (nonisolated) and notification callbacks.
    // nonisolated(unsafe) allows cross-isolation access. Safety: during
    // normal operation all access is serialized by @MainActor; during
    // deinit exclusive access is guaranteed (no other references exist).
    nonisolated(unsafe) private var process: (any SidecarProcessProtocol)?
    nonisolated(unsafe) private var eventContinuation:
        AsyncThrowingStream<AgentEvent, Error>.Continuation?
    nonisolated(unsafe) private var eventStreamTask: Task<Void, Never>?
    nonisolated(unsafe) private var pendingResponses:
        [Int: CheckedContinuation<RpcResponse, Error>] = [:]
    private let lock = NSLock()
    nonisolated(unsafe) private var terminationObserver: Any?

    init(processFactory: @escaping @Sendable () -> any SidecarProcessProtocol) {
        self.processFactory = processFactory
        observeAppTermination()
    }

    convenience init(sidecarScript: String) {
        self.init(processFactory: { SidecarProcess(sidecarScript: sidecarScript) })
    }

    deinit {
        if let observer = terminationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        performCleanup()
    }

    // MARK: - Public API

    func startSession(
        prompt: String,
        workingDirectory: String,
        systemPrompt: String? = nil,
        permissionMode: PermissionMode = .default,
        allowedTools: [String]? = nil,
        resumeSessionId: String? = nil
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        guard status == .idle else {
            return AsyncThrowingStream {
                $0.finish(throwing: SidecarBridgeError.sessionAlreadyActive)
            }
        }

        let id = UUID().uuidString
        let (stream, continuation) = AsyncThrowingStream<AgentEvent, Error>.makeStream()

        self.sessionId = id
        self.status = .starting
        self.eventContinuation = continuation

        Task { [weak self] in
            guard let self else {
                continuation.finish(throwing: SidecarBridgeError.deallocated)
                return
            }

            do {
                if !(self.process?.isRunning == true) {
                    let proc = self.processFactory()
                    try proc.start()
                    self.process = proc
                    self.startEventLoop()
                }

                let params = StartSessionParams(
                    sessionId: id,
                    prompt: prompt,
                    workingDirectory: workingDirectory,
                    systemPrompt: systemPrompt,
                    permissionMode: permissionMode,
                    allowedTools: allowedTools,
                    resumeSessionId: resumeSessionId
                )

                let response = try await self.sendRpc(
                    method: "start_session", params: params
                )
                if case .failure(let rpcError) = response.outcome {
                    self.status = .error(rpcError.message)
                    self.sessionId = nil
                    self.eventContinuation = nil
                    continuation.finish(throwing: rpcError)
                }
            } catch {
                self.status = .error(error.localizedDescription)
                self.sessionId = nil
                self.eventContinuation = nil
                continuation.finish(throwing: error)
            }
        }

        return stream
    }

    func sendMessage(_ message: String) async throws {
        guard status == .running, let sessionId, process?.isRunning == true else {
            throw SidecarBridgeError.noActiveSession
        }

        let params = SendMessageParams(sessionId: sessionId, message: message)
        let response = try await sendRpc(method: "send_message", params: params)
        if case .failure(let rpcError) = response.outcome {
            throw rpcError
        }
    }

    func cancel() async {
        guard status == .running, let sessionId, process?.isRunning == true else {
            return
        }

        status = .cancelling
        let params = CancelSessionParams(sessionId: sessionId)
        _ = try? await sendRpc(method: "cancel_session", params: params)
    }

    func shutdown() {
        performCleanup()
        sessionId = nil
        sdkSessionId = nil
        status = .idle
    }

    // MARK: - Private

    private func startEventLoop() {
        guard let process else { return }

        eventStreamTask = Task { [weak self] in
            for await message in process.events {
                guard let self, !Task.isCancelled else { break }
                self.handleMessage(message)
            }

            guard let self, !Task.isCancelled else { return }
            self.failPendingResponses(with: SidecarBridgeError.processExited)

            switch self.status {
            case .idle, .error:
                break
            default:
                self.status = .error("Process terminated unexpectedly")
                self.eventContinuation?.finish(
                    throwing: SidecarBridgeError.processExited
                )
                self.eventContinuation = nil
            }
        }
    }

    private func handleMessage(_ message: SidecarMessage) {
        switch message {
        case .response(let response):
            lock.lock()
            let continuation = pendingResponses.removeValue(forKey: response.id)
            lock.unlock()
            continuation?.resume(returning: response)

        case .event(let notification):
            guard notification.sessionId == sessionId else { return }

            switch notification.event {
            case .sessionStarted(let sdkId):
                sdkSessionId = sdkId
                status = .running
                eventContinuation?.yield(notification.event)

            case .sessionComplete:
                eventContinuation?.yield(notification.event)
                eventContinuation?.finish()
                eventContinuation = nil
                sessionId = nil
                sdkSessionId = nil
                status = .idle

            case .sessionError(let error):
                if status == .cancelling {
                    // Cancel triggers session_error — treat as clean completion
                    eventContinuation?.yield(notification.event)
                    eventContinuation?.finish()
                    eventContinuation = nil
                    sessionId = nil
                    sdkSessionId = nil
                    status = .idle
                } else {
                    status = .error(error)
                    eventContinuation?.yield(notification.event)
                    eventContinuation?.finish(
                        throwing: SidecarBridgeError.sessionError(error)
                    )
                    eventContinuation = nil
                }

            default:
                eventContinuation?.yield(notification.event)
            }
        }
    }

    @discardableResult
    private func sendRpc<P: Encodable>(
        method: String, params: P
    ) async throws -> RpcResponse {
        guard let process else { throw SidecarBridgeError.noActiveSession }

        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            do {
                let requestId = try process.send(method: method, params: params)
                pendingResponses[requestId] = continuation
                lock.unlock()
            } catch {
                lock.unlock()
                continuation.resume(throwing: error)
            }
        }
    }

    private func failPendingResponses(with error: Error) {
        lock.lock()
        let pending = pendingResponses
        pendingResponses.removeAll()
        lock.unlock()

        for (_, continuation) in pending {
            continuation.resume(throwing: error)
        }
    }

    /// Non-isolated cleanup: cancels tasks, terminates process, and resumes
    /// pending continuations. Safe to call from deinit and notification handlers.
    nonisolated private func performCleanup() {
        eventStreamTask?.cancel()
        eventStreamTask = nil
        process?.terminate()
        process = nil
        eventContinuation?.finish()
        eventContinuation = nil

        lock.lock()
        let pending = pendingResponses
        pendingResponses.removeAll()
        lock.unlock()
        for (_, cont) in pending {
            cont.resume(throwing: SidecarBridgeError.shutdown)
        }
    }

    private func observeAppTermination() {
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.performCleanup()
        }
    }
}

// MARK: - ChatBridgeProtocol

@MainActor
protocol ChatBridgeProtocol: AnyObject {
    var status: SidecarBridge.SessionStatus { get }
    func startSession(
        prompt: String,
        workingDirectory: String,
        systemPrompt: String?,
        permissionMode: PermissionMode,
        allowedTools: [String]?,
        resumeSessionId: String?
    ) -> AsyncThrowingStream<AgentEvent, Error>
    func sendMessage(_ message: String) async throws
    func cancel() async
}

extension SidecarBridge: ChatBridgeProtocol {}

// MARK: - Errors

enum SidecarBridgeError: Error, Equatable {
    case noActiveSession
    case sessionAlreadyActive
    case processExited
    case shutdown
    case deallocated
    case sessionError(String)
}
