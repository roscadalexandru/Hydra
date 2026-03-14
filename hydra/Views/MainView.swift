import SwiftUI
import GRDB

struct MainView: View {
    let workspaceId: Int64

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
    @State private var workingDirectory: String?
    @State private var bridge: SidecarBridge?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("Chat")
            if let bridge {
                ChatView(
                    bridge: bridge,
                    workspaceId: workspaceId,
                    workingDirectory: workingDirectory ?? NSHomeDirectory()
                )
            } else {
                Text("Loading chat...")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            await loadWorkspace()
        }
    }

    private func loadWorkspace() async {
        do {
            let dir = try await AppDatabase.shared.dbWriter.read { db -> String? in
                let project = try Project
                    .filter(Project.Columns.workspaceId == workspaceId)
                    .fetchOne(db)
                return project?.path
            }
            workingDirectory = dir
            if bridge == nil {
                bridge = SidecarBridge(sidecarScript: "sidecar/index.js")
            }
        } catch {
            print("Failed to load workspace: \(error)")
        }
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
