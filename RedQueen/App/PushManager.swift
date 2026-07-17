import Foundation
import Observation
import OSLog
import UserNotifications
import MatrixRustSDK
#if os(iOS)
import UIKit
#endif

private let log = Logger(subsystem: "info.pich.redqueen", category: "Push")

/// Requests notification permission, registers the APNs token as a Matrix
/// HTTP pusher (via Sygnal), and routes notification taps to their room.
@MainActor @Observable
final class PushManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = PushManager()

    /// Room to open because the user tapped a notification.
    var pendingRoomID: String?

    private var client: Client?
    private var gatewayURL = AppConfig.defaultPushGatewayURL

    /// Called early (app launch) so cold-start notification taps are caught.
    func installDelegate() {
        UNUserNotificationCenter.current().delegate = self
    }

    /// Asks for permission and kicks off APNs registration.
    func start(client: Client, gatewayURL: String) async {
        self.client = client
        self.gatewayURL = gatewayURL

        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard granted else {
            log.info("Notification permission not granted; skipping pusher registration")
            return
        }
        #if os(iOS)
        UIApplication.shared.registerForRemoteNotifications()
        #endif
    }

    /// APNs token arrived — register it with the homeserver.
    /// Sygnal's default config base64-decodes the pushkey, so encode as base64.
    func handleDeviceToken(_ token: Data) {
        guard let client else { return }
        let pushkey = token.base64EncodedString()
        let appID = AppConfig.pusherAppID
        let gatewayURL = gatewayURL
        Task {
            do {
                try await client.setPusher(
                    identifiers: PusherIdentifiers(pushkey: pushkey, appId: appID),
                    kind: .http(data: HttpPusherData(url: gatewayURL, format: nil, defaultPayload: nil)),
                    appDisplayName: AppConfig.agentDisplayName,
                    deviceDisplayName: AppConfig.deviceDisplayName,
                    profileTag: nil,
                    lang: Locale.current.language.languageCode?.identifier ?? "en",
                    append: false)
                log.info("Pusher registered with \(appID, privacy: .public) at \(gatewayURL, privacy: .public)")
            } catch {
                log.error("setPusher failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func handleRegistrationFailure(_ error: Error) {
        log.error("APNs registration failed: \(error.localizedDescription, privacy: .public)")
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        guard let roomID = userInfo["room_id"] as? String else { return }
        await MainActor.run {
            pendingRoomID = roomID
        }
    }
}
