import SwiftUI

struct ComposerView: View {
    @Binding var text: String
    let onSend: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Message Red Queen…", text: $text, axis: .vertical)
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

            Button(action: sendIfPossible) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(canSend ? Color.reAccent : Color.reMuted.opacity(0.4))
            }
            .disabled(!canSend)
            .padding(.trailing, 6)
            .padding(.bottom, 4)
        }
        .background(Color.reSurface, in: .rect(cornerRadius: 22))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendIfPossible() {
        guard canSend else { return }
        onSend()
    }
}
