import SwiftUI

struct ChatSessionRowView: View {
    let session: ChatSession
    let isSelected: Bool
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            statusIndicator

            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(.system(.body, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)

                Text(relativeTimestamp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contextMenu {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var statusIndicator: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
    }

    private var statusColor: Color {
        switch session.status {
        case .active: .green
        case .completed: .gray
        case .failed: .red
        case .cancelled: .orange
        }
    }

    private var relativeTimestamp: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: session.updatedAt, relativeTo: Date())
    }
}
