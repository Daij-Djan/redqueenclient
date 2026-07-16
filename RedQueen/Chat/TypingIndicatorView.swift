import SwiftUI

/// "Red Queen is thinking" — agent-styled row with three pulsing dots,
/// shown in the message flow while the other side is typing.
struct TypingIndicatorView: View {
    @State private var animating = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            BotAvatarView(size: 28)

            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.reAccent.opacity(0.9))
                        .frame(width: 7, height: 7)
                        .scaleEffect(animating ? 1 : 0.55)
                        .opacity(animating ? 1 : 0.4)
                        .animation(.easeInOut(duration: 0.5)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.18),
                            value: animating)
                }
            }

            Spacer()
        }
        .onAppear { animating = true }
        .accessibilityLabel("\(AppConfig.agentDisplayName) is typing")
    }
}

#Preview {
    TypingIndicatorView()
        .padding()
}
