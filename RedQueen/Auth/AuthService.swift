import Foundation
import MatrixRustSDK

/// Builds SDK clients for fresh logins and restored sessions.
enum AuthService {
    static func login(username: String, password: String) async throws -> (client: Client, stored: StoredSession) {
        let storeID = UUID().uuidString
        let client = try await ClientBuilder()
            .serverNameOrHomeserverUrl(serverNameOrUrl: AppConfig.homeserverURL)
            .sessionPaths(dataPath: URL.sessionData(for: storeID).path(percentEncoded: false),
                          cachePath: URL.sessionCaches(for: storeID).path(percentEncoded: false))
            .slidingSyncVersionBuilder(versionBuilder: .discoverNative)
            .build()

        try await client.login(username: username, password: password,
                               initialDeviceName: AppConfig.deviceDisplayName, deviceId: nil)

        let stored = StoredSession(session: try client.session(), storeID: storeID)
        return (client, stored)
    }

    static func restore(_ stored: StoredSession) async throws -> Client {
        let client = try await ClientBuilder()
            .sessionPaths(dataPath: URL.sessionData(for: stored.storeID).path(percentEncoded: false),
                          cachePath: URL.sessionCaches(for: stored.storeID).path(percentEncoded: false))
            .homeserverUrl(url: stored.homeserverURL)
            .build()

        try await client.restoreSession(session: stored.sdkSession)
        return client
    }

    static func removeSessionStores(storeID: String) {
        try? FileManager.default.removeItem(at: .sessionData(for: storeID))
        try? FileManager.default.removeItem(at: .sessionCaches(for: storeID))
    }
}

extension URL {
    static func sessionData(for storeID: String) -> URL {
        .applicationSupportDirectory.appending(components: "RedQueen", storeID)
    }

    static func sessionCaches(for storeID: String) -> URL {
        .cachesDirectory.appending(components: "RedQueen", storeID)
    }
}
