import SwiftUI

struct ComposerView: View {
    @Binding var text: String
    let onSend: () -> Void
    /// When set, the composer offers voice recording while the field is empty.
    var recorder: VoiceRecorder?
    var onSendVoice: ((VoiceRecorder.Recording) -> Void)?
    /// When set, the composer offers image attachments.
    var pendingImages: Binding<[PendingImage]>?
    var onPickLibrary: (() -> Void)?
    var onPickCamera: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            if let pendingImages, !pendingImages.wrappedValue.isEmpty {
                PendingImageStrip(images: pendingImages)
            }
            if let recorder, recorder.isRecording {
                recordingBar(recorder)
            } else {
                inputBar
            }
        }
        .background(Color.reSurface, in: .rect(cornerRadius: 22))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if onPickLibrary != nil || onPickCamera != nil {
                Menu {
                    if let onPickLibrary {
                        Button(action: onPickLibrary) {
                            Label("Photo Library", systemImage: "photo.on.rectangle")
                        }
                    }
                    if let onPickCamera {
                        Button(action: onPickCamera) {
                            Label("Camera", systemImage: "camera")
                        }
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(Color.reMuted)
                }
                .accessibilityLabel("Add attachment")
                .padding(.leading, 8)
                .padding(.bottom, 6)
            }

            TextField(AppConfig.composerPlaceholder, text: $text, axis: .vertical)
                .lineLimit(1...6)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .onSubmit(sendIfPossible)
                // Hardware keyboards: Enter sends, Shift+Enter inserts a newline.
                .onKeyPress(phases: .down) { press in
                    guard press.key == .return, press.modifiers.isDisjoint(with: [.shift, .option]) else {
                        return .ignored
                    }
                    sendIfPossible()
                    return .handled
                }

            if canSend || recorder == nil {
                Button(action: sendIfPossible) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(canSend ? Color.reAccent : Color.reMuted.opacity(0.4))
                }
                .disabled(!canSend)
                .padding(.trailing, 6)
                .padding(.bottom, 4)
            } else if let recorder {
                Button {
                    Task {
                        if await !recorder.start() {
                            text = "" // permission denied; nothing to do
                        }
                    }
                } label: {
                    Image(systemName: "mic.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(Color.reAccent)
                }
                .accessibilityLabel("Record voice message")
                .padding(.trailing, 6)
                .padding(.bottom, 4)
            }
        }
    }

    private func recordingBar(_ recorder: VoiceRecorder) -> some View {
        HStack(spacing: 12) {
            Button {
                _ = recorder.stop(discard: true)
            } label: {
                Image(systemName: "trash.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.reMuted)
            }
            .accessibilityLabel("Discard recording")
            .padding(.leading, 14)

            Circle()
                .fill(Color.reAccent)
                .frame(width: 10, height: 10)
                .scaleEffect(1 + CGFloat(recorder.currentLevel) * 1.5)
                .animation(.easeOut(duration: 0.1), value: recorder.currentLevel)

            Text(Self.format(recorder.duration))
                .font(.callout.monospacedDigit())
                .foregroundStyle(Color.reMuted)

            Spacer()

            Button {
                if let recording = recorder.stop() {
                    onSendVoice?(recording)
                }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Color.reAccent)
            }
            .accessibilityLabel("Send voice message")
            .padding(.trailing, 6)
        }
        .frame(minHeight: 46)
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !(pendingImages?.wrappedValue.isEmpty ?? true)
    }

    private func sendIfPossible() {
        guard canSend else { return }
        onSend()
    }

    private static func format(_ duration: TimeInterval) -> String {
        let seconds = Int(duration)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
