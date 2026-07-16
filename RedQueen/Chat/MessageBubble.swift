import SwiftUI

/// ChatGPT-style message rendering: the agent speaks full-width with an
/// avatar; the user's messages are right-aligned bubbles.
struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        if message.isOwn {
            HStack {
                Spacer(minLength: 60)
                Text(markdown)
                    .textSelection(.enabled)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.reSurface, in: .rect(cornerRadius: 18))
            }
        } else {
            HStack(alignment: .top, spacing: 10) {
                BotAvatarView(size: 28)
                Text(markdown)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
        }
    }

    private var markdown: AttributedString {
        (try? AttributedString(markdown: message.text,
                               options: .init(allowsExtendedAttributes: true,
                                              interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(message.text)
    }
}

#Preview {
    VStack(spacing: 16) {
        MessageBubble(message: ChatMessage(id: "1", eventID: nil, sender: "@dominik:x", isOwn: true,
                                           text: "Hello Red Queen", isEdited: false, timestamp: .now))
        MessageBubble(message: ChatMessage(id: "2", eventID: nil, sender: "@redqueen:x", isOwn: false,
                                           text: "**Off with their heads!** How can I help you today?",
                                           isEdited: false, timestamp: .now))
    }
    .padding()
}
