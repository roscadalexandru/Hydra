import SwiftUI
import GRDB
import Combine

@Observable
final class WelcomeViewModel {
    var workspaces: [Workspace] = []

    private let database: AppDatabase
    private var cancellable: AnyCancellable?

    nonisolated deinit { }

    init(database: AppDatabase = .shared) {
        self.database = database
        observeWorkspaces()
    }

    func createWorkspace(name: String) -> Int64? {
        var workspace = Workspace(name: name)
        do {
            try database.dbWriter.write { db in
                try workspace.insert(db)
            }
            return workspace.id
        } catch {
            print("Failed to create workspace: \(error)")
            return nil
        }
    }

    func updateLastOpened(_ workspaceId: Int64) {
        do {
            try database.dbWriter.write { db in
                if var workspace = try Workspace.fetchOne(db, key: workspaceId) {
                    workspace.lastOpenedAt = Date()
                    try workspace.update(db)
                }
            }
        } catch {
            print("Failed to update lastOpenedAt: \(error)")
        }
    }

    func deleteWorkspace(_ workspaceId: Int64) {
        do {
            _ = try database.dbWriter.write { db in
                try Workspace.deleteOne(db, key: workspaceId)
            }
        } catch {
            print("Failed to delete workspace: \(error)")
        }
    }

    private func observeWorkspaces() {
        let observation = ValueObservation.tracking { db in
            try Workspace
                .order(sql: "lastOpenedAt DESC NULLS LAST, createdAt DESC")
                .fetchAll(db)
        }

        cancellable = observation
            .publisher(in: database.dbWriter, scheduling: .async(onQueue: .main))
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { [weak self] workspaces in
                    self?.workspaces = workspaces
                }
            )
    }
}

struct WelcomeView: View {
    @State private var viewModel = WelcomeViewModel()
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var showingCreate = false
    @State private var newWorkspaceName = ""
    @State private var workspaceToDelete: Workspace?
    @State private var openWorkspaceIds: Set<Int64> = []

    var body: some View {
        VStack(spacing: 0) {
            header
            workspaceList
            Divider()
            bottomBar
        }
        .sheet(isPresented: $showingCreate) {
            createSheet
        }
        .alert(
            "Delete Workspace",
            isPresented: Binding(
                get: { workspaceToDelete != nil },
                set: { if !$0 { workspaceToDelete = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) {
                workspaceToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let id = workspaceToDelete?.id {
                    viewModel.deleteWorkspace(id)
                }
                workspaceToDelete = nil
            }
        } message: {
            if let workspace = workspaceToDelete {
                Text("Are you sure you want to delete \"\(workspace.name)\"? All projects, epics, and issues in this workspace will be permanently deleted.")
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "drop.halffull")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Hydra")
                .font(.largeTitle.bold())
            Text("Select a workspace or create a new one")
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 32)
    }

    private var workspaceList: some View {
        List(viewModel.workspaces) { workspace in
            WorkspaceRow(workspace: workspace)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    if let id = workspace.id {
                        openWorkspace(id)
                    }
                }
                .contextMenu {
                    Button("Delete", role: .destructive) {
                        workspaceToDelete = workspace
                    }
                }
        }
    }

    private var bottomBar: some View {
        HStack {
            Button("Create Workspace") {
                showingCreate = true
            }
            Spacer()
        }
        .padding(12)
    }

    private var createSheet: some View {
        VStack(spacing: 16) {
            Text("New Workspace")
                .font(.headline)
            TextField("Workspace name", text: $newWorkspaceName)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Cancel") {
                    newWorkspaceName = ""
                    showingCreate = false
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create") {
                    if !newWorkspaceName.isEmpty {
                        if let id = viewModel.createWorkspace(name: newWorkspaceName) {
                            newWorkspaceName = ""
                            showingCreate = false
                            openWorkspace(id)
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newWorkspaceName.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 350)
    }

    private func openWorkspace(_ id: Int64) {
        guard !openWorkspaceIds.contains(id) else { return }
        openWorkspaceIds.insert(id)
        viewModel.updateLastOpened(id)
        openWindow(value: id)
        dismissWindow(id: "welcome")
    }
}

private struct WorkspaceRow: View {
    let workspace: Workspace

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(workspace.name)
                .font(.headline)
            if let lastOpened = workspace.lastOpenedAt {
                Text("Last opened \(lastOpened, style: .relative) ago")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Never opened")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}
