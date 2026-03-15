import SwiftUI

struct ChatView: View {
    @State private var viewModel: ChatViewModel

    init(bridge: ChatBridgeProtocol, workspaceId: Int64, workingDirectory: String) {
        _viewModel = State(initialValue: ChatViewModel(
            bridge: bridge,
            workspaceId: workspaceId,
            workingDirectory: workingDirectory
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
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
        .sheet(item: Binding(
            get: { viewModel.pendingPermissionRequest },
            set: { newValue in
                if newValue == nil {
                    viewModel.respondToPermission(approved: false)
                }
            }
        )) { request in
            PermissionRequestView(
                request: request,
                onApprove: { viewModel.respondToPermission(approved: true) },
                onDeny: { viewModel.respondToPermission(approved: false) }
            )
        }
    }
}
