import SwiftUI

struct PermissionRequestView: View {
    let request: ChatViewModel.PermissionRequestInfo
    let onApprove: () -> Void
    let onDeny: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Permission Required", systemImage: "lock.shield")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Tool") {
                    Text(request.toolName)
                        .font(.body.monospaced())
                }

                Text(request.description)
                    .font(.body)
                    .foregroundStyle(.secondary)

                if !request.affectedPaths.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Affected paths:")
                            .font(.subheadline.bold())
                        ForEach(request.affectedPaths, id: \.self) { path in
                            Text(path)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            HStack {
                Button("Deny", role: .cancel) {
                    onDeny()
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button("Approve") {
                    onApprove()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}
