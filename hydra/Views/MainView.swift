import SwiftUI

struct MainView: View {
    let workspaceId: Int64

    var body: some View {
        HSplitView {
            BoardPane(workspaceId: workspaceId)
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
    var body: some View {
        VSplitView {
            VStack(alignment: .leading, spacing: 0) {
                header("Terminal")
                Text("SwiftTerm terminal goes here")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(minHeight: 200)

            VStack(alignment: .leading, spacing: 0) {
                header("Chat")
                Text("Chat interface goes here")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(minHeight: 200)
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
