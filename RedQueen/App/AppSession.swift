import Foundation
import Observation
import MatrixRustSDK
import CocoaLumberjackSwift

/// Owns the SDK `Client` and sync loop for the lifetime of a login.
@MainActor @Observable
final class AppSession {
    enum State {
        case launching
        case loggedOut
        case active
    }

    private(set) var state: State = .launching
    private(set) var client: Client?
    private(set) var userID: String?
    private(set) var syncService: SyncService?

    private var storeID: String?
    private var syncStateHandle: TaskHandle?

    /// Restores a persisted session if one exists; otherwise shows login.
    func launch() async {
        guard let stored = KeychainStore.loadSession() else {
            DDLogInfo("🔑 [AppSession] launch: no stored session, showing login")
            state = .loggedOut
            return
        }
        do {
            let client = try await AuthService.restore(stored)
            try await activate(client, storeID: stored.storeID)
            DDLogInfo("🔑 [AppSession] launch: restored session for \(self.userID ?? "?")")
        } catch {
            // Session is unusable (revoked token, wiped store) — start over.
            DDLogError("💥 [AppSession] launch: restore FAILED, clearing session: \(error)")
            KeychainStore.clearSession()
            AuthService.removeSessionStores(storeID: stored.storeID)
            state = .loggedOut
        }
    }

    func login(username: String, password: String) async throws {
        DDLogInfo("🔑 [AppSession] login attempt for \(username)")
        do {
            let (client, stored) = try await AuthService.login(username: username, password: password)
            try KeychainStore.save(stored)
            try await activate(client, storeID: stored.storeID)
            DDLogInfo("🔑 [AppSession] login succeeded for \(self.userID ?? "?")")
        } catch {
            DDLogError("💥 [AppSession] login FAILED: \(error)")
            throw error
        }
    }

    func logout() async {
        DDLogInfo("🔑 [AppSession] logout")
        if let client {
            do {
                try await client.logout()
            } catch {
                DDLogError("💥 [AppSession] logout: client.logout() FAILED: \(error)")
            }
        }
        await syncService?.stop()
        if let storeID {
            AuthService.removeSessionStores(storeID: storeID)
        }
        KeychainStore.clearSession()
        client = nil
        syncService = nil
        userID = nil
        storeID = nil
        state = .loggedOut
    }

    private final class SyncStateLogger: SyncServiceStateObserver {
        func onUpdate(state: SyncServiceState) {
            DDLogInfo("🔄 [AppSession] sync service state: \(String(describing: state))")
        }
    }

    private func activate(_ client: Client, storeID: String) async throws {
        self.client = client
        self.storeID = storeID
        do {
            userID = try client.userId()
        } catch {
            DDLogError("💥 [AppSession] activate: client.userId() FAILED: \(error)")
            userID = nil
        }

        let syncService = try await client.syncService().finish()
        self.syncService = syncService
        syncStateHandle = syncService.state(listener: SyncStateLogger())
        await syncService.start()

        state = .active
    }
}
