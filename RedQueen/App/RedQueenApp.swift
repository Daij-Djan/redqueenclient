import SwiftUI

@main
struct RedQueenApp: App {
    @State private var appSession = AppSession()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appSession)
        }
    }
}

struct RootView: View {
    @Environment(AppSession.self) private var appSession

    var body: some View {
        switch appSession.state {
        case .launching:
            VStack(spacing: 16) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.red.gradient)
                ProgressView()
            }
            .task { await appSession.launch() }
        case .loggedOut:
            LoginView()
        case .active:
            MainView()
        }
    }
}
