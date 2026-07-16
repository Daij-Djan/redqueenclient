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

            Button(action: sendIfPossible) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(canSend ? Color.red : Color.gray.opacity(0.5))
            }
            .disabled(!canSend)
            .padding(.trailing, 6)
            .padding(.bottom, 4)
        }
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 22))
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
