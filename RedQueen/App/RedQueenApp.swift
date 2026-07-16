import SwiftUI

@main
struct RedQueenApp: App {
    @State private var appSession = AppSession()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appSession)
                .preferredColorScheme(.dark)
                .tint(.reAccent)
        }
    }
}

struct RootView: View {
    @Environment(AppSession.self) private var appSession

    var body: some View {
        Group {
            switch appSession.state {
            case .launching:
                VStack(spacing: 16) {
                    BotAvatarView(size: 96)
                    ProgressView()
                        .tint(.reMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(REBackground())
                .task { await appSession.launch() }
            case .loggedOut:
                LoginView()
            case .active:
                MainView()
            }
        }
    }
}
