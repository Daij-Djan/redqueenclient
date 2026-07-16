import SwiftUI

/// ChatGPT-style message rendering: the agent speaks full-width with an
/// avatar; the user's messages are right-aligned bubbles.
struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        if message.isOwn {
            HStack {
                Spacer(minLength: 60)
                bubbleContent
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.reSurface, in: .rect(cornerRadius: 18))
            }
        } else {
            HStack(alignment: .top, spacing: 10) {
                BotAvatarView(size: 28)
                bubbleContent
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    private var bubbleContent: some View {
        switch message.content {
        case .text(let text):
            Text(Self.markdown(text))
                .textSelection(.enabled)
        case .audio(let attachment):
            VoiceMessageRow(message: message, attachment: attachment)
        }
    }

    static func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text,
                               options: .init(allowsExtendedAttributes: true,
                                              interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}

/// Play/pause row for voice notes and audio attachments.
struct VoiceMessageRow: View {
    let message: ChatMessage
    let attachment: AudioAttachment

    @Environment(AudioPlayerService.self) private var audioPlayer

    private var isPlaying: Bool { audioPlayer.playingMessageID == message.id }
    private var isLoading: Bool { audioPlayer.loadingMessageID == message.id }

    var body: some View {
        Button {
            audioPlayer.toggle(messageID: message.id, attachment: attachment)
        } label: {
            HStack(spacing: 10) {
                Group {
                    if isLoading {
                        ProgressView()
                    } else {
                        Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(Color.reAccent)
                    }
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(attachment.isVoice ? "Voice message" : attachment.filename)
                        .font(.callout)
                        .lineLimit(1)
                    if let duration = attachment.duration {
                        Text(Self.format(duration))
                            .font(.caption)
                            .foregroundStyle(Color.reMuted)
                            .monospacedDigit()
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private static func format(_ duration: TimeInterval) -> String {
        let seconds = Int(duration.rounded())
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

#Preview {
    VStack(spacing: 16) {
        MessageBubble(message: ChatMessage(id: "1", eventID: nil, sender: "@dominik:x", isOwn: true,
                                           content: .text("Hello Red Queen"), isEdited: false, timestamp: .now))
        MessageBubble(message: ChatMessage(id: "2", eventID: nil, sender: "@hermes:x", isOwn: false,
                                           content: .text("**Off with their heads!** How can I help you today?"),
                                           isEdited: false, timestamp: .now))
    }
    .padding()
    .background(Color.reBackground)
    .environment(AudioPlayerService())
}
