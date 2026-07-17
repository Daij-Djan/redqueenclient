import Foundation
import MatrixRustSDK

enum AppConfig {
    // MARK: Branding

    /// The agent's user-facing name, used across titles and labels.
    static let agentDisplayName = "Red Queen"
    /// Placeholder shown in message composers.
    static let composerPlaceholder = "Message \(agentDisplayName)…"
    /// Greeting on the cold-start home screen.
    static let homeGreeting = "What can I do for you?"
    /// Device name shown in the homeserver's session list.
    static let deviceDisplayName = "\(agentDisplayName) Client"

    // MARK: Server & agent

    /// The homeserver every login is pre-filled with.
    static let homeserverURL = "https://matrix.roesrath-kleineichen.de"

    /// Default Matrix user ID of the Hermes agent ("Red Queen"), on the same
    /// homeserver as the logged-in user. Overridable at runtime in Settings.
    static func defaultAgentUserID(ownUserID: String?) -> String {
        if let ownUserID, let colon = ownUserID.firstIndex(of: ":") {
            return "@hermes\(ownUserID[colon...])"
        }
        return "@hermes:matrix.roesrath-kleineichen.de"
    }

    /// Whether newly created agent conversations are end-to-end encrypted.
    /// Off until Hermes E2EE support is confirmed.
    static let encryptNewConversations = false

    /// Element Call web app used for voice/video, overridable in Settings.
    /// Works with any MatrixRTC-capable homeserver; the LiveKit backend comes
    /// from the homeserver's .well-known (livekit.roesrath-kleineichen.de).
    static let defaultElementCallURL = "https://call.element.io"

    /// Sygnal push gateway notify endpoint, overridable in Settings.
    static let defaultPushGatewayURL = "https://matrix.roesrath-kleineichen.de/_matrix/push/v1/notify"

    /// Pusher app ID as configured in Sygnal. Debug builds get APNs sandbox
    /// tokens, so they must use the `.dev` entry (sandbox platform in Sygnal).
    static var pusherAppID: String {
        #if DEBUG
        "info.pich.redqueen.ios.dev"
        #else
        "info.pich.redqueen.ios"
        #endif
    }

    /// Version of the bundled Matrix Rust SDK, to show in Settings.
    static var sdkVersion: String { MatrixRustSDK.sdkGitSha() }
}
