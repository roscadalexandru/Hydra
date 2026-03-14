import SwiftUI

struct MessageBubbleView: View {
    let message: ChatMessage

    var body: some View {
        switch message.role {
        case .user:
            userBubble
        case .assistant:
            assistantBubble
        case .toolUse:
            toolUseBubble
        case .toolResult:
            toolResultBubble
        }
    }

    private var userBubble: some View {
        HStack {
            Spacer()
            Text(message.content)
                .padding(8)
                .background(Color.accentColor.opacity(0.2))
                .cornerRadius(8)
        }
    }

    private var assistantBubble: some View {
        HStack {
            Text(message.content)
                .textSelection(.enabled)
                .padding(8)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
            Spacer()
        }
    }

    private var toolUseBubble: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Label(message.toolName ?? "Tool", systemImage: "wrench")
                    .font(.caption.bold())
                if let input = message.toolInput, !input.isEmpty {
                    Text(input)
                        .font(.caption2.monospaced())
                        .lineLimit(3)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)
            Spacer()
        }
    }

    private var toolResultBubble: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Label(
                    message.isError ? "Error" : "Result",
                    systemImage: message.isError ? "xmark.circle" : "checkmark.circle"
                )
                .font(.caption.bold())
                .foregroundStyle(message.isError ? .red : .green)

                Text(message.content)
                    .font(.caption2.monospaced())
                    .lineLimit(3)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(8)
            Spacer()
        }
    }
}

// MARK: - Streaming Bubble

struct StreamingBubbleView: View {
    let text: String

    var body: some View {
        HStack {
            Text(text)
                .textSelection(.enabled)
                .padding(8)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
            Spacer()
        }
    }
}
