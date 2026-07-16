import SwiftUI

/// Gemini-style cold-start screen: a big centered composer. Sending creates a
/// fresh conversation and drops straight into it.
struct HomeView: View {
    let isCreating: Bool
    let onSubmit: (String) -> Void
    let onSubmitVoice: (VoiceRecorder.Recording) -> Void
    let onShowConversations: () -> Void

    @State private var text = ""
    @State private var recorder = VoiceRecorder()
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            BotAvatarView(size: 120, glow: 2)
                .padding(.bottom, 16)

            Text(AppConfig.homeGreeting)
                .font(.title2.bold())
                .padding(.bottom, 28)

            Group {
                if recorder.isRecording {
                    recordingBar
                } else {
                    inputBar
                }
            }
            .background(Color.reSurface, in: .rect(cornerRadius: 26))
            .frame(maxWidth: 560)
            .padding(.horizontal, 20)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(REBackground())
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: onShowConversations) {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("Conversations")
            }
        }
        .onAppear { isFocused = true }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(AppConfig.composerPlaceholder, text: $text, axis: .vertical)
                .lineLimit(1...8)
                .focused($isFocused)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                // Hardware keyboards: Enter sends, Shift+Enter inserts a newline.
                .onKeyPress(phases: .down) { press in
                    guard press.key == .return, press.modifiers.isDisjoint(with: [.shift, .option]) else {
                        return .ignored
                    }
                    submit()
                    return .handled
                }

            if isCreating {
                ProgressView()
                    .frame(width: 34, height: 34)
                    .padding(.trailing, 8)
                    .padding(.bottom, 8)
            } else if canSend {
                Button(action: submit) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(Color.reAccent)
                }
                .padding(.trailing, 8)
                .padding(.bottom, 8)
            } else {
                Button {
                    Task { _ = await recorder.start() }
                } label: {
                    Image(systemName: "mic.circle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(Color.reAccent)
                }
                .accessibilityLabel("Record voice message")
                .padding(.trailing, 8)
                .padding(.bottom, 8)
            }
        }
    }

    private var recordingBar: some View {
        HStack(spacing: 12) {
            Button {
                _ = recorder.stop(discard: true)
            } label: {
                Image(systemName: "trash.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.reMuted)
            }
            .accessibilityLabel("Discard recording")
            .padding(.leading, 18)

            Circle()
                .fill(Color.reAccent)
                .frame(width: 11, height: 11)
                .scaleEffect(1 + CGFloat(recorder.currentLevel) * 1.5)
                .animation(.easeOut(duration: 0.1), value: recorder.currentLevel)

            Text(Self.format(recorder.duration))
                .font(.callout.monospacedDigit())
                .foregroundStyle(Color.reMuted)

            Spacer()

            Button {
                if let recording = recorder.stop() {
                    onSubmitVoice(recording)
                }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Color.reAccent)
            }
            .accessibilityLabel("Send voice message")
            .padding(.trailing, 8)
        }
        .frame(minHeight: 62)
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func format(_ duration: TimeInterval) -> String {
        let seconds = Int(duration)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func submit() {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        onSubmit(message)
    }
}

#Preview {
    NavigationStack {
        HomeView(isCreating: false, onSubmit: { _ in }, onSubmitVoice: { _ in }, onShowConversations: {})
    }
}
