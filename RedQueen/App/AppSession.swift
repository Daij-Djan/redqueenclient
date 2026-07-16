import Foundation
import Observation
import OSLog
import MatrixRustSDK

private let log = Logger(subsystem: "info.pich.redqueen", category: "Session")

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
            state = .loggedOut
            return
        }
        do {
            let client = try await AuthService.restore(stored)
            try await activate(client, storeID: stored.storeID)
        } catch {
            // Session is unusable (revoked token, wiped store) — start over.
            KeychainStore.clearSession()
            AuthService.removeSessionStores(storeID: stored.storeID)
            state = .loggedOut
        }
    }

    func login(username: String, password: String) async throws {
        let (client, stored) = try await AuthService.login(username: username, password: password)
        try KeychainStore.save(stored)
        try await activate(client, storeID: stored.storeID)
    }

    func logout() async {
        if let client {
            try? await client.logout()
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
            log.info("Sync service state: \(String(describing: state), privacy: .public)")
        }
    }

    private func activate(_ client: Client, storeID: String) async throws {
        self.client = client
        self.storeID = storeID
        userID = try? client.userId()

        let syncService = try await client.syncService().finish()
        self.syncService = syncService
        syncStateHandle = syncService.state(listener: SyncStateLogger())
        await syncService.start()

        state = .active
    }
}
