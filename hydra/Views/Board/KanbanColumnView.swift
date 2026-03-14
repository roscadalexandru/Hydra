import SwiftUI

struct KanbanColumnView: View {
    let status: Issue.Status
    let issues: [Issue]
    let onDrop: (Issue, Issue.Status) -> Void
    var onSelect: ((Issue) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            columnHeader
                .padding(.horizontal, 8)
                .padding(.vertical, 10)

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(issues) { issue in
                        IssueCardView(issue: issue)
                            .onTapGesture { onSelect?(issue) }
                            .draggable(issue.transferRepresentation) {
                                IssueCardView(issue: issue)
                                    .frame(width: 200)
                                    .opacity(0.8)
                            }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.background.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .dropDestination(for: String.self) { items, _ in
            guard let idString = items.first, let id = Int64(idString) else { return false }
            if let issue = issues.first(where: { $0.id == id }) {
                onDrop(issue, status)
            } else {
                let placeholder = Issue(id: id, workspaceId: 0, title: "")
                onDrop(placeholder, status)
            }
            return true
        }
    }

    private var columnHeader: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(status.displayName)
                .font(.subheadline)
                .fontWeight(.semibold)
            Text("\(issues.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(.quaternary)
                .clipShape(Capsule())
            Spacer()
        }
    }

    private var statusColor: Color {
        switch status {
        case .backlog: .gray
        case .inProgress: .blue
        case .inReview: .orange
        case .done: .green
        }
    }
}

extension Issue.Status {
    var displayName: String {
        switch self {
        case .backlog: "Backlog"
        case .inProgress: "In Progress"
        case .inReview: "In Review"
        case .done: "Done"
        }
    }
}

extension Issue {
    var transferRepresentation: String {
        "\(id ?? 0)"
    }
}
