import SwiftUI
import GRDB
import Combine

struct MainView: View {
    let workspaceId: Int64
    @State private var showingSettings = false

    var body: some View {
        HSplitView {
            BoardPane(workspaceId: workspaceId)
                .frame(minWidth: 300, idealWidth: 400)

            ObservationPane()
                .frame(minWidth: 250, idealWidth: 350)

            RightPane(workspaceId: workspaceId)
                .frame(minWidth: 300, idealWidth: 400)
        }
        .frame(minWidth: 1000, minHeight: 600)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gear")
                }
                .help("Workspace Settings")
            }
        }
        .sheet(isPresented: $showingSettings) {
            WorkspaceSettingsView(workspaceId: workspaceId)
        }
    }
}

// MARK: - Board Pane (Left)

struct BoardPane: View {
    let workspaceId: Int64

    var body: some View {
        BoardView(workspaceId: workspaceId)
    }
}

// MARK: - Observation Pane (Center)

struct ObservationPane: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("Observation")
            Text("File tree, diffs, activity log")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Right Pane (Terminal + Chat)

struct RightPane: View {
    let workspaceId: Int64

    var body: some View {
        VSplitView {
            VStack(alignment: .leading, spacing: 0) {
                header("Terminal")
                Text("SwiftTerm terminal goes here")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(minHeight: 200)

            ChatPane(workspaceId: workspaceId)
                .frame(minHeight: 200)
        }
    }
}

// MARK: - Chat Pane

struct ChatPane: View {
    let workspaceId: Int64
    @State private var projectPaths: [String] = []
    @State private var bridge: SidecarBridge?
    @State private var projectCancellable: AnyCancellable?

    private var workingDirectory: String {
        projectPaths.first ?? NSHomeDirectory()
    }

    private var additionalDirectories: [String] {
        Array(projectPaths.dropFirst())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("Chat")
            if let bridge {
                ChatView(
                    bridge: bridge,
                    workspaceId: workspaceId,
                    workingDirectory: workingDirectory,
                    additionalDirectories: additionalDirectories
                )
            } else {
                Text("Loading chat...")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            observeProjects()
            if bridge == nil {
                bridge = SidecarBridge(sidecarScript: "sidecar/src/index.js")
            }
        }
    }

    private func observeProjects() {
        let observation = ValueObservation.tracking { db -> [String] in
            let projects = try Project
                .filter(Project.Columns.workspaceId == workspaceId)
                .order(Project.Columns.name)
                .fetchAll(db)
            return projects.map(\.path)
        }

        projectCancellable = observation
            .publisher(in: AppDatabase.shared.dbWriter, scheduling: .async(onQueue: .main))
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { [self] paths in
                    projectPaths = paths
                }
            )
    }
}

// MARK: - Shared

private func header(_ title: String) -> some View {
    Text(title)
        .font(.headline)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
}

#Preview {
    MainView(workspaceId: 1)
}
