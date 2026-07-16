import Foundation
import MatrixRustSDK

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
    /// caller can navigate straight into it.
    static func createConversationRoom(client: Client, agentUserID: String) async throws -> Room {
        let roomID = try await createConversation(client: client, agentUserID: agentUserID)
        return try await client.awaitRoomRemoteEcho(roomId: roomID)
    }

    /// Names a conversation after its first user message, like ChatGPT history titles.
    static func autoName(room: Room, firstMessage: String) async {
        let title = String(firstMessage.prefix(40))
        try? await room.setName(name: title)
    }
}
