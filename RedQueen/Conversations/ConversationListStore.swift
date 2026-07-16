import Foundation
import Observation
import MatrixRustSDK

/// A room shown in the drawer.
struct Conversation: Identifiable, Equatable {
    let id: String
    var displayName: String
    var isAgentRoom: Bool

    static func == (lhs: Conversation, rhs: Conversation) -> Bool {
        lhs.id == rhs.id && lhs.displayName == rhs.displayName && lhs.isAgentRoom == rhs.isAgentRoom
    }
}

/// Mirrors the SDK's room list into observable, drawer-ready state.
@MainActor @Observable
final class ConversationListStore {
    private(set) var conversations: [Conversation] = []
    private(set) var otherRooms: [Conversation] = []

    private var rooms: [Room] = []
    private var agentMembership: [String: Bool] = [:]
    private var agentUserID = ""
    private var entriesHandle: RoomListEntriesWithDynamicAdaptersResult?

    func start(syncService: SyncService, agentUserID: String) async throws {
        self.agentUserID = agentUserID
        let roomList = try await syncService.roomListService().allRooms()
        let listener = RoomListListenerProxy { [weak self] updates in
            Task { @MainActor in self?.apply(updates) }
        }
        entriesHandle = roomList.entriesWithDynamicAdapters(pageSize: 200, listener: listener)
        _ = entriesHandle?.controller().setFilter(kind: .all(filters: [.nonLeft]))
    }

    func room(withID id: String) -> Room? {
        rooms.first { $0.id() == id }
    }

    /// Re-evaluates a single room's agent membership, e.g. after creating a chat.
    func refreshMembership(roomID: String) {
        agentMembership[roomID] = nil
        rebuild()
    }

    private func apply(_ updates: [RoomListEntriesUpdate]) {
        for update in updates {
            switch update {
            case .append(let values): rooms.append(contentsOf: values)
            case .clear: rooms.removeAll()
            case .pushFront(let room): rooms.insert(room, at: 0)
            case .pushBack(let room): rooms.append(room)
            case .popFront: if !rooms.isEmpty { rooms.removeFirst() }
            case .popBack: if !rooms.isEmpty { rooms.removeLast() }
            case .insert(let index, let room): rooms.insert(room, at: Int(index))
            case .set(let index, let room): rooms[Int(index)] = room
            case .remove(let index): rooms.remove(at: Int(index))
            case .truncate(let length): rooms.removeSubrange(Int(length)..<rooms.count)
            case .reset(let values): rooms = values
            }
        }
        rebuild()
    }

    /// Rooms arrive sorted by recency from the SDK; split them into agent
    /// conversations and everything else, resolving membership lazily.
    private func rebuild() {
        var conversations: [Conversation] = []
        var others: [Conversation] = []

        for room in rooms {
            let id = room.id()
            let name = room.displayName() ?? id
            switch agentMembership[id] {
            case .some(true):
                conversations.append(Conversation(id: id, displayName: name, isAgentRoom: true))
            case .some(false):
                others.append(Conversation(id: id, displayName: name, isAgentRoom: false))
            case .none:
                // Unknown yet — resolve in the background, then rebuild.
                others.append(Conversation(id: id, displayName: name, isAgentRoom: false))
                resolveMembership(room: room, roomID: id)
            }
        }

        self.conversations = conversations
        self.otherRooms = others
    }

    private func resolveMembership(room: Room, roomID: String) {
        agentMembership[roomID] = false
        Task { [agentUserID] in
            let isAgentRoom: Bool
            do {
                let member = try await room.member(userId: agentUserID)
                isAgentRoom = member.membership == .join || member.membership == .invite
            } catch {
                isAgentRoom = false
            }
            if isAgentRoom {
                agentMembership[roomID] = true
                rebuild()
            }
        }
    }
}

/// Bridges the SDK's callback protocol to a closure.
private final class RoomListListenerProxy: RoomListEntriesListener {
    private let onUpdateClosure: ([RoomListEntriesUpdate]) -> Void

    init(onUpdate: @escaping ([RoomListEntriesUpdate]) -> Void) {
        onUpdateClosure = onUpdate
    }

    func onUpdate(roomEntriesUpdate: [RoomListEntriesUpdate]) {
        onUpdateClosure(roomEntriesUpdate)
    }
}
