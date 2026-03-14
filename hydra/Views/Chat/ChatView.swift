import SwiftUI
import GRDB

struct ChatView: View {
    @State private var viewModel: ChatViewModel
    @State private var sessionListViewModel: ChatSessionListViewModel
    @State private var showSidebar: Bool = true
    @State private var selectedProjectId: Int64?
    @State private var projects: [Project] = []

    private let database: AppDatabase
    private let bridge: ChatBridgeProtocol
    private let workspaceId: Int64
    private let workingDirectory: String

    init(
        database: AppDatabase = .shared,
        bridge: ChatBridgeProtocol,
        workspaceId: Int64,
        workingDirectory: String
    ) {
        self.database = database
        self.bridge = bridge
        self.workspaceId = workspaceId
        self.workingDirectory = workingDirectory

        _viewModel = State(initialValue: ChatViewModel(
            database: database,
            bridge: bridge,
            workspaceId: workspaceId,
            workingDirectory: workingDirectory
        ))
        _sessionListViewModel = State(initialValue: ChatSessionListViewModel(
            database: database,
            workspaceId: workspaceId
        ))
    }

    var body: some View {
        HSplitView {
            if showSidebar {
                ChatSidebarView(
                    viewModel: sessionListViewModel,
                    onSelectSession: { session in
                        viewModel.loadSession(session)
                        viewModel.projectId = session.projectId
                        selectedProjectId = session.projectId
                    },
                    onNewChat: {
                        createNewChat()
                    }
                )
                .frame(minWidth: 200, idealWidth: 250, maxWidth: 300)
            }

            VStack(spacing: 0) {
                ChatHeaderView(
                    sessionTitle: viewModel.session?.title ?? "New Chat",
                    projects: projects,
                    selectedProjectId: $selectedProjectId
                )

                Divider()

                MessageListView(
                    messages: viewModel.messages,
                    streamingText: viewModel.streamingText,
                    isStreaming: viewModel.isStreaming
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                ChatInputView(
                    text: $viewModel.inputText,
                    isStreaming: viewModel.isStreaming,
                    onSend: { viewModel.send() },
                    onCancel: { viewModel.cancelSession() }
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation { showSidebar.toggle() }
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .help(showSidebar ? "Hide Sidebar" : "Show Sidebar")
            }
        }
        .task {
            try? await sessionListViewModel.loadSessions()
            await loadProjects()
            viewModel.onSessionCreated = { session in
                sessionListViewModel.sessions.insert(session, at: 0)
                sessionListViewModel.selectSession(session)
            }
        }
        .onChange(of: sessionListViewModel.selectedSessionId) { _, newId in
            if newId == nil {
                viewModel.resetSession()
                selectedProjectId = nil
            }
        }
        .onChange(of: selectedProjectId) { oldValue, newProjectId in
            guard oldValue != newProjectId,
                  let session = viewModel.session,
                  session.projectId != newProjectId else { return }
            viewModel.session?.projectId = newProjectId
            viewModel.projectId = newProjectId
            Task {
                try? await sessionListViewModel.updateSessionProject(session, projectId: newProjectId)
            }
        }
    }

    private func createNewChat() {
        Task {
            let session = try? await sessionListViewModel.createSession(projectId: selectedProjectId)
            if let session {
                sessionListViewModel.selectSession(session)
                viewModel.loadSession(session)
            }
        }
    }

    private func loadProjects() async {
        do {
            let wsId = workspaceId
            projects = try await database.dbWriter.read { db in
                try Project
                    .filter(Column("workspaceId") == wsId)
                    .order(Column("name").asc)
                    .fetchAll(db)
            }
        } catch {
            projects = []
        }
    }
}
