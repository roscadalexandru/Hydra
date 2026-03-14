import SwiftUI

struct ChatHeaderView: View {
    let sessionTitle: String
    let projects: [Project]
    @Binding var selectedProjectId: Int64?
    let sidecarStatus: SidecarBridge.SessionStatus

    var body: some View {
        HStack(spacing: 12) {
            Text(sessionTitle)
                .font(.headline)
                .lineLimit(1)

            sidecarStatusBadge

            Spacer()

            Picker("Project", selection: $selectedProjectId) {
                Text("No Project").tag(nil as Int64?)
                ForEach(projects) { project in
                    Text(project.name).tag(project.id as Int64?)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 200)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var sidecarStatusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(sidecarStatusColor)
                .frame(width: 6, height: 6)
            Text(sidecarStatusLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.quaternary)
        .clipShape(Capsule())
    }

    private var sidecarStatusColor: Color {
        switch sidecarStatus {
        case .idle: .gray
        case .starting: .yellow
        case .running: .green
        case .cancelling: .orange
        case .error: .red
        }
    }

    private var sidecarStatusLabel: String {
        switch sidecarStatus {
        case .idle: "Idle"
        case .starting: "Starting..."
        case .running: "Connected"
        case .cancelling: "Cancelling..."
        case .error(let msg): "Error: \(msg)"
        }
    }
}
