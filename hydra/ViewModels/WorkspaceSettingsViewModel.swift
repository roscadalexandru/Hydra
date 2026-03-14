import SwiftUI
import GRDB
import Combine

@Observable
final class WorkspaceSettingsViewModel {
    var workspace: Workspace?
    var projects: [Project] = []

    private let workspaceId: Int64
    private let database: AppDatabase
    private var workspaceCancellable: AnyCancellable?
    private var projectsCancellable: AnyCancellable?

    nonisolated deinit { }

    init(workspaceId: Int64, database: AppDatabase = .shared) {
        self.workspaceId = workspaceId
        self.database = database
        observeWorkspace()
        observeProjects()
    }

    func updateWorkspace(
        name: String? = nil,
        description: String? = nil,
        autonomyMode: Workspace.AutonomyMode? = nil
    ) {
        let database = self.database
        let workspaceId = self.workspaceId
        Task.detached {
            do {
                try await database.dbWriter.write { db in
                    if var ws = try Workspace.fetchOne(db, key: workspaceId) {
                        if let name { ws.name = name }
                        if let description { ws.description = description }
                        if let autonomyMode { ws.defaultAutonomyMode = autonomyMode }
                        ws.updatedAt = Date()
                        try ws.update(db)
                    }
                }
            } catch {
                print("Failed to update workspace: \(error)")
            }
        }
    }

    func addProject(name: String, path: String) {
        let database = self.database
        let workspaceId = self.workspaceId
        Task.detached {
            do {
                try await database.dbWriter.write { db in
                    var project = Project(workspaceId: workspaceId, name: name, path: path)
                    try project.insert(db)
                }
            } catch {
                print("Failed to add project: \(error)")
            }
        }
    }

    func removeProject(_ projectId: Int64) {
        let database = self.database
        Task.detached {
            do {
                _ = try await database.dbWriter.write { db in
                    try Project.deleteOne(db, key: projectId)
                }
            } catch {
                print("Failed to remove project: \(error)")
            }
        }
    }

    private func observeWorkspace() {
        let observation = ValueObservation.tracking { [workspaceId] db in
            try Workspace.fetchOne(db, key: workspaceId)
        }

        workspaceCancellable = observation
            .publisher(in: database.dbWriter, scheduling: .async(onQueue: .main))
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { [weak self] workspace in
                    self?.workspace = workspace
                }
            )
    }

    private func observeProjects() {
        let observation = ValueObservation.tracking { [workspaceId] db in
            try Project
                .filter(Project.Columns.workspaceId == workspaceId)
                .order(Project.Columns.name)
                .fetchAll(db)
        }

        projectsCancellable = observation
            .publisher(in: database.dbWriter, scheduling: .async(onQueue: .main))
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { [weak self] projects in
                    self?.projects = projects
                }
            )
    }
}
