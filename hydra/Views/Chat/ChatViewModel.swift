import Foundation
import GRDB
import Combine

@Observable
@MainActor
final class ChatViewModel {
    var messages: [ChatMessage] = []
    var streamingText: String = ""
    var isStreaming: Bool = false
    var inputText: String = ""
    var session: ChatSession?
    var errorMessage: String?

    private let database: AppDatabase
    private let bridge: ChatBridgeProtocol
    private let workspaceId: Int64
    private let workingDirectory: String
    private var cancellable: AnyCancellable?
    private var streamTask: Task<Void, Never>?
    private var nextOrderIndex: Int = 0

    init(
        database: AppDatabase = .shared,
        bridge: ChatBridgeProtocol,
        workspaceId: Int64,
        workingDirectory: String
    ) {
        self.database = database
        self.bridge = bridge
        self.workspaceId = workspaceId
        self.workingDirectory = workingDirectory
    }

    // MARK: - Public

    func send() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        inputText = ""

        // Create session if needed
        if session == nil {
            var newSession = ChatSession(workspaceId: workspaceId)
            do {
                try database.dbWriter.write { db in
                    try newSession.insert(db)
                }
                session = newSession
                observeMessages()
            } catch {
                errorMessage = "Failed to create session: \(error.localizedDescription)"
                return
            }
        }

        // Persist user message
        persistMessage(role: .user, content: text)

        // Start streaming if not already active
        if !isStreaming {
            isStreaming = true
            let stream = bridge.startSession(
                prompt: text,
                workingDirectory: workingDirectory,
                systemPrompt: nil,
                permissionMode: .default,
                allowedTools: nil,
                resumeSessionId: nil
            )
            consumeStream(stream)
        }
    }

    func cancelSession() {
        Task { await bridge.cancel() }
    }

    // MARK: - Stream Consumption

    private func consumeStream(_ stream: AsyncThrowingStream<AgentEvent, Error>) {
        streamTask = Task { [weak self] in
            do {
                for try await event in stream {
                    guard let self else { return }
                    self.handleEvent(event)
                }
                self?.finalizeStreaming()
            } catch {
                self?.handleStreamError(error)
            }
        }
    }

    private func handleEvent(_ event: AgentEvent) {
        switch event {
        case .sessionStarted(let sdkId):
            session?.sdkSessionId = sdkId
            updateSession()

        case .textDelta(let delta):
            streamingText += delta

        case .assistantMessage(let content):
            persistMessage(role: .assistant, content: content)
            streamingText = ""

        case .toolUse(let toolName, let toolId, let input):
            let inputJson = serializeAnyCodableValue(input)
            persistMessage(role: .toolUse, content: toolName, toolName: toolName, toolId: toolId, toolInput: inputJson)

        case .toolResult(let toolId, let result, let isError):
            let resultJson = serializeAnyCodableValue(result)
            persistMessage(role: .toolResult, content: resultJson, toolId: toolId, isError: isError)

        case .sessionComplete(let durationMs, let costUsd):
            session?.status = .completed
            session?.totalDurationMs = durationMs
            session?.totalCostUsd = costUsd
            updateSession()
            finalizeStreaming()

        case .sessionError(let error):
            errorMessage = error
            session?.status = .failed
            updateSession()
            finalizeStreaming()
        }
    }

    private func finalizeStreaming() {
        isStreaming = false
        streamingText = ""
        streamTask = nil
    }

    private func handleStreamError(_ error: Error) {
        errorMessage = error.localizedDescription
        session?.status = .failed
        updateSession()
        finalizeStreaming()
    }

    // MARK: - Persistence

    private func persistMessage(
        role: ChatMessage.Role,
        content: String,
        toolName: String? = nil,
        toolId: String? = nil,
        toolInput: String? = nil,
        isError: Bool = false
    ) {
        guard let sessionId = session?.id else { return }
        var message = ChatMessage(
            chatSessionId: sessionId,
            orderIndex: nextOrderIndex,
            role: role,
            content: content,
            toolName: toolName,
            toolId: toolId,
            toolInput: toolInput,
            isError: isError
        )
        nextOrderIndex += 1
        let db = database
        Task.detached {
            do {
                try await db.dbWriter.write { dbConn in
                    try message.insert(dbConn)
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.errorMessage = "Failed to save message: \(error.localizedDescription)"
                }
            }
        }
    }

    private func updateSession() {
        guard var s = session else { return }
        s.updatedAt = Date()
        session = s
        let db = database
        Task.detached {
            do {
                try await db.dbWriter.write { dbConn in
                    try s.update(dbConn)
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.errorMessage = "Failed to update session: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Observation

    private func observeMessages() {
        guard let sessionId = session?.id else { return }
        let observation = ValueObservation.tracking { db in
            try ChatMessage
                .filter(ChatMessage.Columns.chatSessionId == sessionId)
                .order(ChatMessage.Columns.orderIndex.asc)
                .fetchAll(db)
        }
        cancellable = observation
            .publisher(in: database.dbWriter, scheduling: .async(onQueue: .main))
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { [weak self] messages in
                    self?.messages = messages
                }
            )
    }

    // MARK: - Serialization

    private func serializeAnyCodableValue(_ value: AnyCodableValue) -> String {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(value),
              let str = String(data: data, encoding: .utf8) else {
            return ""
        }
        return str
    }
}
