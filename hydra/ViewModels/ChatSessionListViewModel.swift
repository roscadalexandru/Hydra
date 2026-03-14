import Foundation
import GRDB

@Observable
@MainActor
final class ChatSessionListViewModel {
    nonisolated deinit { }

    var sessions: [ChatSession] = []
    var selectedSessionId: Int64?

    private let database: AppDatabase
    private let workspaceId: Int64

    init(database: AppDatabase = .shared, workspaceId: Int64) {
        self.database = database
        self.workspaceId = workspaceId
    }

    func loadSessions() async throws {
        sessions = try await database.dbWriter.read { db in
            try ChatSession.fetchAllForWorkspace(db, workspaceId: self.workspaceId)
        }
    }

    @discardableResult
    func createSession(projectId: Int64? = nil) async throws -> ChatSession {
        var session = ChatSession(workspaceId: workspaceId, projectId: projectId)
        try await database.dbWriter.write { db in
            try session.insert(db)
        }
        sessions.insert(session, at: 0)
        return session
    }

    func deleteSession(_ session: ChatSession) async throws {
        try await database.dbWriter.write { db in
            _ = try session.delete(db)
        }
        sessions.removeAll { $0.id == session.id }
        if selectedSessionId == session.id {
            selectedSessionId = nil
        }
    }

    func selectSession(_ session: ChatSession?) {
        selectedSessionId = session?.id
    }

    func updateSessionTitle(_ session: ChatSession, title: String) async throws {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        var updated = sessions[index]
        updated.title = title
        updated.updatedAt = Date()
        try await database.dbWriter.write { db in
            try updated.update(db)
        }
        sessions[index] = updated
    }

    func updateSessionProject(_ session: ChatSession, projectId: Int64?) async throws {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        var updated = sessions[index]
        updated.projectId = projectId
        updated.updatedAt = Date()
        try await database.dbWriter.write { db in
            try updated.update(db)
        }
        sessions[index] = updated
    }
}
