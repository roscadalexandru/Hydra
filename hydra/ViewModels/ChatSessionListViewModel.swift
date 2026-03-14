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
        let wsId = workspaceId
        let db = database
        sessions = try await Task.detached {
            try await db.dbWriter.read { dbConn in
                try ChatSession.fetchAllForWorkspace(dbConn, workspaceId: wsId)
            }
        }.value
    }

    @discardableResult
    func createSession(projectId: Int64? = nil) async throws -> ChatSession {
        var session = ChatSession(workspaceId: workspaceId, projectId: projectId)
        let db = database
        try await Task.detached {
            try await db.dbWriter.write { dbConn in
                try session.insert(dbConn)
            }
        }.value
        sessions.insert(session, at: 0)
        return session
    }

    func deleteSession(_ session: ChatSession) async throws {
        let db = database
        try await Task.detached {
            try await db.dbWriter.write { dbConn in
                _ = try session.delete(dbConn)
            }
        }.value
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
        let db = database
        let u = updated
        try await Task.detached {
            try await db.dbWriter.write { dbConn in
                try u.update(dbConn)
            }
        }.value
        sessions[index] = updated
    }

    func updateSessionProject(_ session: ChatSession, projectId: Int64?) async throws {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        var updated = sessions[index]
        updated.projectId = projectId
        updated.updatedAt = Date()
        let db = database
        let u = updated
        try await Task.detached {
            try await db.dbWriter.write { dbConn in
                try u.update(dbConn)
            }
        }.value
        sessions[index] = updated
    }
}
