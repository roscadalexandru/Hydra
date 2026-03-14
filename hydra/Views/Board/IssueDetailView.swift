import SwiftUI

struct IssueDetailView: View {
    @Binding var issue: Issue
    let onSave: (Issue) -> Void
    let onDelete: (Issue) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var description: String = ""
    @State private var status: Issue.Status = .backlog
    @State private var priority: Issue.Priority = .medium
    @State private var assigneeType: String = "human"
    @State private var assigneeName: String = ""
    @State private var showDeleteConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            detailToolbar
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    titleSection
                    statusAndPrioritySection
                    assigneeSection
                    descriptionSection
                }
                .padding(20)
            }
        }
        .frame(width: 480)
        .frame(minHeight: 500)
        .onAppear { loadIssue() }
        .alert("Delete Issue", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                onDelete(issue)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete \"\(issue.title)\"?")
        }
    }

    // MARK: - Toolbar

    private var detailToolbar: some View {
        HStack {
            Text("Issue Detail")
                .font(.headline)
            Spacer()
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            Button("Save") { save() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    // MARK: - Title

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Title")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TextField("Issue title", text: $title)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
        }
    }

    // MARK: - Status & Priority

    private var statusAndPrioritySection: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Status")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Picker("Status", selection: $status) {
                    ForEach(Issue.Status.allCases, id: \.self) { s in
                        Text(s.displayName).tag(s)
                    }
                }
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Priority")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Picker("Priority", selection: $priority) {
                    ForEach(Issue.Priority.allCases, id: \.self) { p in
                        HStack {
                            Circle()
                                .fill(priorityColor(p))
                                .frame(width: 8, height: 8)
                            Text(p.rawValue.capitalized)
                        }
                        .tag(p)
                    }
                }
                .labelsHidden()
            }

            Spacer()
        }
    }

    // MARK: - Assignee

    private var assigneeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Assignee")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Picker("Type", selection: $assigneeType) {
                    Text("Human").tag("human")
                    Text("Agent").tag("agent")
                }
                .pickerStyle(.segmented)
                .frame(width: 160)

                if assigneeType == "human" {
                    TextField("Name", text: $assigneeName)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    // MARK: - Description

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Description")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TextEditor(text: $description)
                .font(.body)
                .frame(minHeight: 150)
                .padding(4)
                .background(.background.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(.separator, lineWidth: 0.5)
                )
        }
    }

    // MARK: - Helpers

    private func loadIssue() {
        title = issue.title
        description = issue.description
        status = issue.status
        priority = issue.priority
        assigneeType = issue.assigneeType
        assigneeName = issue.assigneeName
    }

    private func save() {
        issue.title = title
        issue.description = description
        issue.status = status
        issue.priority = priority
        issue.assigneeType = assigneeType
        issue.assigneeName = assigneeName
        issue.updatedAt = Date()
        onSave(issue)
        dismiss()
    }

    private func priorityColor(_ p: Issue.Priority) -> Color {
        switch p {
        case .urgent: .red
        case .high: .orange
        case .medium: .blue
        case .low: .gray
        }
    }
}
