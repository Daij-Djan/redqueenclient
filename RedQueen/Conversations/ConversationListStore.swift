import Foundation
import Observation
import UserNotifications
import MatrixRustSDK

/// A room shown in the drawer.
struct Conversation: Identifiable, Equatable {
    let id: String
    var displayName: String
    var isAgentRoom: Bool
    /// "Interesting" messages received since the last read receipt — drives
    /// the unread badge in the list.
    var unreadCount: UInt64

    static func == (lhs: Conversation, rhs: Conversation) -> Bool {
        lhs.id == rhs.id && lhs.displayName == rhs.displayName
            && lhs.isAgentRoom == rhs.isAgentRoom && lhs.unreadCount == rhs.unreadCount
    }
}

/// Mirrors the SDK's room list into observable, drawer-ready state.
@MainActor @Observable
final class ConversationListStore {
    private(set) var conversations: [Conversation] = []
    private(set) var otherRooms: [Conversation] = []

    private var rooms: [Room] = []
    private var agentMembership: [String: Bool] = [:]
    private var unreadCounts: [String: UInt64] = [:]
    private var roomInfoHandles: [String: TaskHandle] = [:]
    private var lastBadgeCount = -1
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

    /// Forces the app icon badge back to the real unread total. Call when
    /// the app becomes active — a background push may have stamped the OS
    /// badge with whatever count the push gateway guessed, bypassing our
    /// own tracking entirely.
    func resyncBadge() {
        updateAppBadge(force: true)
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
        syncRoomInfoSubscriptions()
        rebuild()
    }

    /// Rooms arrive sorted by recency from the SDK; split them into agent
    /// conversations and everything else, resolving membership lazily.
    private func rebuild() {
        var conversations: [Conversation] = []
        var others: [Conversation] = []
        let activeRoomID = PushManager.shared.activeRoomID

        for room in rooms {
            let id = room.id()
            let name = room.displayName() ?? id
            let unread = id == activeRoomID ? 0 : (unreadCounts[id] ?? 0)
            switch agentMembership[id] {
            case .some(true):
                conversations.append(Conversation(id: id, displayName: name, isAgentRoom: true, unreadCount: unread))
            case .some(false):
                others.append(Conversation(id: id, displayName: name, isAgentRoom: false, unreadCount: unread))
            case .none:
                // Unknown yet — resolve in the background, then rebuild.
                others.append(Conversation(id: id, displayName: name, isAgentRoom: false, unreadCount: unread))
                resolveMembership(room: room, roomID: id)
            }
        }

        self.conversations = conversations
        self.otherRooms = others
        updateAppBadge()
    }

    /// Keeps one `RoomInfo` subscription per room currently in the list, so
    /// the unread badge tracks the server's read state live — dropped rooms
    /// get their subscription cancelled instead of leaking.
    private func syncRoomInfoSubscriptions() {
        let currentIDs = Set(rooms.map { $0.id() })

        for id in roomInfoHandles.keys where !currentIDs.contains(id) {
            roomInfoHandles[id]?.cancel()
            roomInfoHandles[id] = nil
            unreadCounts[id] = nil
        }

        for room in rooms where roomInfoHandles[room.id()] == nil {
            let id = room.id()
            let listener = RoomInfoListenerProxy { [weak self] info in
                Task { @MainActor in self?.applyUnreadCount(roomID: id, info: info) }
            }
            roomInfoHandles[id] = room.subscribeToRoomInfoUpdates(listener: listener)
        }
    }

    private func applyUnreadCount(roomID: String, info: RoomInfo) {
        unreadCounts[roomID] = info.numUnreadMessages
        rebuild()
    }

    /// Mirrors the icon badge to what the list actually shows unread, instead
    /// of whatever count the push gateway last guessed — reading a
    /// conversation (or opening the app and having it sync) clears it. The
    /// room currently on-screen never counts (zeroed in `rebuild()`) even if
    /// the server's read receipt hasn't caught up yet.
    private func updateAppBadge(force: Bool = false) {
        let total = Int(conversations.reduce(0) { $0 + $1.unreadCount })
        guard force || total != lastBadgeCount else { return }
        lastBadgeCount = total
        Task { try? await UNUserNotificationCenter.current().setBadgeCount(total) }
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

/// Bridges the SDK's per-room info callback to a closure.
private final class RoomInfoListenerProxy: RoomInfoListener {
    private let onCall: (RoomInfo) -> Void

    init(onCall: @escaping (RoomInfo) -> Void) {
        self.onCall = onCall
    }

    func call(roomInfo: RoomInfo) {
        onCall(roomInfo)
    }
}
