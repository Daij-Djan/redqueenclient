import SwiftUI
import CocoaLumberjackSwift

#if os(iOS)
/// Receives APNs registration callbacks and installs the notification
/// delegate early enough to catch cold-start notification taps.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        PushManager.shared.installDelegate()
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushManager.shared.handleDeviceToken(deviceToken)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        PushManager.shared.handleRegistrationFailure(error)
    }
}
#endif

@main
struct RedQueenApp: App {
    @State private var appSession = AppSession()
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    init() {
        AppLogger.start()
    }

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
                .onAppear { DDLogInfo("👁️ [RootView.launching] appeared") }
                .task { await appSession.launch() }
            case .loggedOut:
                LoginView()
                    .onAppear { DDLogInfo("👁️ [RootView.loggedOut] appeared") }
            case .active:
                MainView()
                    .onAppear { DDLogInfo("👁️ [RootView.active] appeared") }
            }
        }
    }
}
