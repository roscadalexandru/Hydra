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
    @Environment(\.dismiss) private var dismiss
    @State private var showingCreate = false
    @State private var newWorkspaceName = ""

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
                    openWorkspace(workspace.id!)
                }
                .contextMenu {
                    Button("Delete", role: .destructive) {
                        viewModel.deleteWorkspace(workspace.id!)
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
        viewModel.updateLastOpened(id)
        openWindow(value: id)
        dismiss()
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
