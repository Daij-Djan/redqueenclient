import SwiftUI

/// Gemini-style cold-start screen: a big centered composer. Sending creates a
/// fresh conversation and drops straight into it.
struct HomeView: View {
    let isCreating: Bool
    let onSubmit: (String) -> Void
    let onShowConversations: () -> Void

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "crown.fill")
                .font(.system(size: 44))
                .foregroundStyle(.red.gradient)
                .padding(.bottom, 12)

            Text("What can I do for you?")
                .font(.title2.bold())
                .padding(.bottom, 28)

            HStack(alignment: .bottom, spacing: 8) {
                TextField("Message Red Queen…", text: $text, axis: .vertical)
                    .lineLimit(1...8)
                    .focused($isFocused)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)

                Button(action: submit) {
                    if isCreating {
                        ProgressView()
                            .frame(width: 34, height: 34)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(canSend ? Color.red : Color.gray.opacity(0.5))
                    }
                }
                .disabled(!canSend || isCreating)
                .padding(.trailing, 8)
                .padding(.bottom, 8)
            }
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 26))
            .frame(maxWidth: 560)
            .padding(.horizontal, 20)

            Spacer()
            Spacer()
        }
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

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        onSubmit(message)
    }
}

#Preview {
    NavigationStack {
        HomeView(isCreating: false, onSubmit: { _ in }, onShowConversations: {})
    }
}
