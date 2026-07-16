import Foundation
import MatrixRustSDK

enum AppConfig {
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

    /// Version of the bundled Matrix Rust SDK, to show in Settings.
    static var sdkVersion: String { MatrixRustSDK.sdkGitSha() }
}
