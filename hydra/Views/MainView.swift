import SwiftUI
import GRDB

struct MainView: View {
    var body: some View {
        HSplitView {
            BoardPane()
                .frame(minWidth: 300, idealWidth: 400)

            ObservationPane()
                .frame(minWidth: 250, idealWidth: 350)

            RightPane()
                .frame(minWidth: 300, idealWidth: 400)
        }
        .frame(minWidth: 1000, minHeight: 600)
    }
}

// MARK: - Board Pane (Left)

struct BoardPane: View {
    var body: some View {
        BoardView()
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
    var body: some View {
        VSplitView {
            VStack(alignment: .leading, spacing: 0) {
                header("Terminal")
                Text("SwiftTerm terminal goes here")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(minHeight: 200)

            ChatPane()
                .frame(minHeight: 200)
        }
    }
}

// MARK: - Chat Pane

struct ChatPane: View {
    @State private var workspaceId: Int64?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("Chat")
            if let workspaceId {
                Text("Chat ready (workspace \(workspaceId))")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("Loading...")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            loadWorkspace()
        }
    }

    private func loadWorkspace() {
        do {
            try AppDatabase.shared.dbWriter.write { db in
                if let existing = try Workspace.fetchOne(db) {
                    workspaceId = existing.id
                }
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
    MainView()
}
