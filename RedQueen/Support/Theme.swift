import SwiftUI

/// Umbrella-control-room palette: black-green depths, laser red, cold mint.
extension Color {
    /// Near-black with a green cast — the app-wide background.
    static let reBackground = Color(red: 0.008, green: 0.035, blue: 0.032)
    /// Lifted greenish surface for fields, bubbles and cards.
    static let reSurface = Color(red: 0.055, green: 0.129, blue: 0.118)
    /// Laser-grid red.
    static let reAccent = Color(red: 1.0, green: 0.161, blue: 0.2)
    /// Pale mint for secondary text.
    static let reMuted = Color(red: 0.62, green: 0.75, blue: 0.72)
    /// Lit teal of the glass walls.
    static let reGlass = Color(red: 0.22, green: 0.82, blue: 0.82)
}

/// The Umbrella control room: black-green depth with glowing teal glass
/// panels. Use as `.background(REBackground())` on full screens.
struct REBackground: View {
    var body: some View {
        ZStack {
            Color.reBackground

            // Distant lit glass walls.
            RadialGradient(colors: [Color.reGlass.opacity(0.13), .clear],
                           center: UnitPoint(x: 0.9, y: 0.12),
                           startRadius: 20, endRadius: 440)
            RadialGradient(colors: [Color.reGlass.opacity(0.08), .clear],
                           center: UnitPoint(x: 0.05, y: 0.78),
                           startRadius: 10, endRadius: 400)

            // Angled glass panes catching the light.
            glassPane(width: 340, height: 190, angle: -14)
                .offset(x: 150, y: -260)
            glassPane(width: 300, height: 150, angle: 10)
                .offset(x: -160, y: 240)
            glassPane(width: 220, height: 110, angle: -6)
                .offset(x: 120, y: 420)
                .opacity(0.7)
        }
        .ignoresSafeArea()
    }

    private func glassPane(width: CGFloat, height: CGFloat, angle: Double) -> some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(LinearGradient(colors: [Color.reGlass.opacity(0.07), Color.reGlass.opacity(0.01)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(LinearGradient(colors: [Color.reGlass.opacity(0.22), .clear],
                                                 startPoint: .top, endPoint: .bottom),
                                  lineWidth: 1)
            }
            .frame(width: width, height: height)
            .rotationEffect(.degrees(angle))
            .blur(radius: 2)
    }
}

#Preview("Background") {
    REBackground()
}

/// The Red Queen's face, with a red glow. `glow` scales the halo (1 = the
/// subtle default used in message rows).
struct BotAvatarView: View {
    var size: CGFloat = 28
    var glow: Double = 1

    var body: some View {
        Image("BotAvatar")
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(.circle)
            .overlay(Circle().strokeBorder(Color.reAccent.opacity(0.6), lineWidth: 1))
            .shadow(color: Color.reAccent.opacity(min(0.45 * glow, 0.9)), radius: size / 6)
            .shadow(color: Color.reAccent.opacity(0.25 * (glow - 1)), radius: size / 3)
    }
}

#Preview {
    HStack(spacing: 20) {
        BotAvatarView(size: 28)
        BotAvatarView(size: 44)
        BotAvatarView(size: 80)
    }
    .padding(40)
    .background(Color.reBackground)
}

/// The laser-red unread pill used in the conversation list. Caps display at
/// "99+" rather than growing unbounded.
struct UnreadBadge: View {
    var count: UInt64

    var body: some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.reAccent))
            .shadow(color: Color.reAccent.opacity(0.6), radius: 4)
    }
}

#Preview("Unread badge") {
    HStack(spacing: 20) {
        UnreadBadge(count: 1)
        UnreadBadge(count: 12)
        UnreadBadge(count: 140)
    }
    .padding(40)
    .background(Color.reBackground)
}
