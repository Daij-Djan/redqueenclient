import Foundation
import OSLog
import MatrixRustSDK

private let log = Logger(subsystem: "info.pich.redqueen", category: "NewChat")

/// Creates a fresh conversation room with the agent, ChatGPT "new chat" style.
enum NewChatService {
    static func createConversation(client: Client, agentUserID: String) async throws -> String {
        let parameters = CreateRoomParameters(name: "New chat",
                                              topic: nil,
                                              isEncrypted: AppConfig.encryptNewConversations,
                                              isDirect: true,
                                              visibility: .private,
                                              preset: .privateChat,
                                              invite: [agentUserID],
                                              avatar: nil)
        return try await client.createRoom(request: parameters)
    }

    /// Creates the room and waits until it lands in the local store, so the
    /// caller can navigate straight into it. Bounded: a wedged sync loop
    /// surfaces as an error instead of an endless wait.
    static func createConversationRoom(client: Client, agentUserID: String) async throws -> Room {
        log.info("Creating room, inviting \(agentUserID, privacy: .public)")
        let roomID = try await createConversation(client: client, agentUserID: agentUserID)
        log.info("Created \(roomID, privacy: .public), awaiting remote echo")

        let room = try await withThrowingTaskGroup(of: Room?.self) { group in
            group.addTask { try await client.awaitRoomRemoteEcho(roomId: roomID) }
            group.addTask {
                try await Task.sleep(for: .seconds(10))
                return nil
            }
            defer { group.cancelAll() }
            guard let first = try await group.next(), let room = first else {
                // Timed out — the room exists server-side; try the local store
                // directly before giving up.
                if let room = try? client.getRoom(roomId: roomID) {
                    log.warning("Remote echo timed out for \(roomID, privacy: .public); using local store")
                    return room
                }
                log.error("Remote echo timed out for \(roomID, privacy: .public); room not in store")
                throw NewChatError.roomDidNotSync
            }
            return room
        }
        log.info("Room \(roomID, privacy: .public) ready")
        return room
    }

    enum NewChatError: LocalizedError {
        case roomDidNotSync

        var errorDescription: String? {
            "The room was created but never arrived over sync. Check the sync connection and try again."
        }
    }

    /// Names a conversation after its first user message, like ChatGPT history titles.
    static func autoName(room: Room, firstMessage: String) async {
        let title = String(firstMessage.prefix(40))
        try? await room.setName(name: title)
    }
}
