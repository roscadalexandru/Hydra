import SwiftUI

struct MessageListView: View {
    let messages: [ChatMessage]
    let streamingText: String
    let isStreaming: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(messages) { message in
                        MessageBubbleView(message: message)
                            .id(message.id)
                    }

                    if isStreaming && !streamingText.isEmpty {
                        StreamingBubbleView(text: streamingText)
                            .id("streaming")
                    }
                }
                .padding()
            }
            .onChange(of: messages.count) {
                if let lastId = messages.last?.id {
                    withAnimation {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
            .onChange(of: streamingText) {
                if isStreaming {
                    withAnimation {
                        proxy.scrollTo("streaming", anchor: .bottom)
                    }
                }
            }
        }
    }
}
