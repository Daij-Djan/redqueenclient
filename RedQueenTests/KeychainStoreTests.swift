import Testing
import MatrixRustSDK
@testable import RedQueen

struct KeychainStoreTests {
    @Test func sessionRoundTrip() throws {
        let session = Session(accessToken: "token",
                              refreshToken: nil,
                              userId: "@dominik:roesrath-kleineichen.de",
                              deviceId: "DEVICE",
                              homeserverUrl: "https://matrix.roesrath-kleineichen.de",
                              oauthData: nil,
                              slidingSyncVersion: .native)
        let stored = StoredSession(session: session, storeID: "test-store")

        try KeychainStore.save(stored)
        defer { KeychainStore.clearSession() }

        let loaded = try #require(KeychainStore.loadSession())
        #expect(loaded.userID == stored.userID)
        #expect(loaded.accessToken == stored.accessToken)
        #expect(loaded.storeID == stored.storeID)
        #expect(loaded.sdkSession.homeserverUrl == session.homeserverUrl)
    }
}
