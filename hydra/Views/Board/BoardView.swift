import SwiftUI

struct BoardView: View {
    @State private var viewModel = BoardViewModel()
    @State private var showingNewIssue = false
    @State private var newIssueTitle = ""
    @State private var newIssuePriority: Issue.Priority = .medium
    @State private var selectedIssue: Issue?

    var body: some View {
        VStack(spacing: 0) {
            boardToolbar
            kanbanBoard
        }
        .onAppear {
            viewModel.ensureWorkspace()
        }
        .sheet(isPresented: $showingNewIssue) {
            newIssueSheet
        }
        .sheet(item: $selectedIssue) { issue in
            IssueDetailView(
                issue: Binding(
                    get: { self.selectedIssue ?? issue },
                    set: { self.selectedIssue = $0 }
                ),
                onSave: { updated in
                    viewModel.updateIssue(updated)
                },
                onDelete: { toDelete in
                    viewModel.deleteIssue(toDelete)
                }
            )
        }
    }

    private var boardToolbar: some View {
        HStack {
            Text("Project Board")
                .font(.headline)
            Spacer()
            Button {
                showingNewIssue = true
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var kanbanBoard: some View {
        HStack(spacing: 8) {
            ForEach(viewModel.columns, id: \.self) { status in
                KanbanColumnView(
                    status: status,
                    issues: viewModel.issues(for: status),
                    onDrop: { issue, newStatus in
                        viewModel.moveIssue(issue, to: newStatus)
                    },
                    onSelect: { issue in
                        selectedIssue = issue
                    }
                )
            }
        }
        .padding(8)
    }

    private var newIssueSheet: some View {
        VStack(spacing: 16) {
            Text("New Issue")
                .font(.headline)

            TextField("Issue title", text: $newIssueTitle)
                .textFieldStyle(.roundedBorder)

            Picker("Priority", selection: $newIssuePriority) {
                ForEach(Issue.Priority.allCases, id: \.self) { p in
                    Text(p.rawValue.capitalized).tag(p)
                }
            }

            HStack {
                Button("Cancel") {
                    newIssueTitle = ""
                    newIssuePriority = .medium
                    showingNewIssue = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Create") {
                    if !newIssueTitle.isEmpty {
                        viewModel.createIssue(title: newIssueTitle, priority: newIssuePriority)
                        newIssueTitle = ""
                        newIssuePriority = .medium
                        showingNewIssue = false
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newIssueTitle.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 350)
    }
}
