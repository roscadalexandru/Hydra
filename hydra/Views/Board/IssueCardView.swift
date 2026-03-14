import SwiftUI

struct IssueCardView: View {
    let issue: Issue

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(issue.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                Spacer()
            }

            HStack(spacing: 8) {
                priorityBadge
                assigneeBadge
            }
        }
        .padding(10)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
    }

    private var priorityBadge: some View {
        Text(issue.priority.rawValue.capitalized)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(priorityColor.opacity(0.2))
            .foregroundStyle(priorityColor)
            .clipShape(Capsule())
    }

    private var assigneeBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: issue.isAgentAssigned ? "cpu" : "person")
                .font(.caption2)
            Text(issue.isAgentAssigned ? "Agent" : (issue.assigneeName.isEmpty ? "Unassigned" : issue.assigneeName))
                .font(.caption2)
        }
        .foregroundStyle(.secondary)
    }

    private var priorityColor: Color {
        switch issue.priority {
        case .urgent: .red
        case .high: .orange
        case .medium: .blue
        case .low: .gray
        }
    }
}
