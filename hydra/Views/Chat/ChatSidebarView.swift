import SwiftUI

struct ChatSidebarView: View {
    @Bindable var viewModel: ChatSessionListViewModel
    let onSelectSession: (ChatSession) -> Void
    let onNewChat: () -> Void

    @State private var deleteError: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header with New Chat button
            HStack {
                Text("Chats")
                    .font(.headline)
                Spacer()
                Button(action: onNewChat) {
                    Image(systemName: "square.and.pencil")
                }
                .buttonStyle(.borderless)
                .help("New Chat")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Session list
            if viewModel.sessions.isEmpty {
                ContentUnavailableView {
                    Label("No Chats", systemImage: "bubble.left.and.bubble.right")
                } description: {
                    Text("Start a new chat to begin.")
                }
                .frame(maxHeight: .infinity)
            } else {
                List(selection: Binding(
                    get: { viewModel.selectedSessionId },
                    set: { newId in
                        if let id = newId, let session = viewModel.sessions.first(where: { $0.id == id }) {
                            viewModel.selectSession(session)
                            onSelectSession(session)
                        }
                    }
                )) {
                    ForEach(viewModel.sessions) { session in
                        ChatSessionRowView(
                            session: session,
                            isSelected: session.id == viewModel.selectedSessionId,
                            onDelete: {
                                Task {
                                    do {
                                        try await viewModel.deleteSession(session)
                                    } catch {
                                        deleteError = error.localizedDescription
                                    }
                                }
                            }
                        )
                        .tag(session.id)
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .alert("Failed to delete session", isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("OK") { deleteError = nil }
        } message: {
            if let deleteError {
                Text(deleteError)
            }
        }
    }
}
