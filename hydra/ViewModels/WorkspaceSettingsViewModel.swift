import SwiftUI
import GRDB
import Combine

@Observable
final class WorkspaceSettingsViewModel {
    var workspace: Workspace?
    var projects: [Project] = []
    var errorMessage: String?

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
        if let name, name.trimmingCharacters(in: .whitespaces).isEmpty {
            return
        }
        let database = self.database
        let workspaceId = self.workspaceId
        Task.detached { [weak self] in
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
                await MainActor.run {
                    self?.errorMessage = "Failed to update workspace: \(error.localizedDescription)"
                }
            }
        }
    }

    func addProject(name: String, path: String) {
        let database = self.database
        let workspaceId = self.workspaceId
        Task.detached { [weak self] in
            do {
                let inserted = try await database.dbWriter.write { db -> Bool in
                    let exists = try Project
                        .filter(Project.Columns.workspaceId == workspaceId)
                        .filter(Project.Columns.path == path)
                        .fetchCount(db) > 0
                    if exists { return false }
                    var project = Project(workspaceId: workspaceId, name: name, path: path)
                    try project.insert(db)
                    return true
                }
                if !inserted {
                    await MainActor.run {
                        self?.errorMessage = "A project at \"\(path)\" already exists in this workspace."
                    }
                }
            } catch {
                await MainActor.run {
                    self?.errorMessage = "Failed to add project: \(error.localizedDescription)"
                }
            }
        }
    }

    func removeProject(_ projectId: Int64) {
        let database = self.database
        Task.detached { [weak self] in
            do {
                _ = try await database.dbWriter.write { db in
                    try Project.deleteOne(db, key: projectId)
                }
            } catch {
                await MainActor.run {
                    self?.errorMessage = "Failed to remove project: \(error.localizedDescription)"
                }
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
