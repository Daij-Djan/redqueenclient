import Foundation
import Observation
import MatrixRustSDK

/// A renderable chat message derived from a timeline item.
struct ChatMessage: Identifiable, Equatable {
    let id: String
    let eventID: String?
    let sender: String
    let isOwn: Bool
    var text: String
    var isEdited: Bool
    let timestamp: Date

    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id && lhs.text == rhs.text && lhs.isEdited == rhs.isEdited
    }
}

/// Mirrors one room's SDK timeline into observable messages.
/// Handles in-place edits (agents stream replies by editing one event).
@MainActor @Observable
final class TimelineStore {
    private(set) var messages: [ChatMessage] = []
    private(set) var isBackPaginating = false
    /// Users currently typing, excluding ourselves — for agent rooms this is
    /// the "Red Queen is thinking" signal.
    private(set) var typingUserIDs: [String] = []

    private var items: [TimelineItem] = []
    private var room: Room?
    private var ownUserID: String?
    private var timeline: Timeline?
    private var listenerHandle: TaskHandle?
    private var typingHandle: TaskHandle?

    func attach(room: Room, ownUserID: String?) async throws {
        self.room = room
        self.ownUserID = ownUserID

        let timeline = try await room.timeline()
        self.timeline = timeline
        let listener = TimelineListenerProxy { [weak self] diffs in
            Task { @MainActor in self?.apply(diffs) }
        }
        listenerHandle = await timeline.addListener(listener: listener)

        typingHandle = room.subscribeToTypingNotifications(listener: TypingListenerProxy { [weak self] userIDs in
            Task { @MainActor in
                guard let self else { return }
                self.typingUserIDs = userIDs.filter { $0 != self.ownUserID }
            }
        })
    }

    func detach() {
        listenerHandle?.cancel()
        listenerHandle = nil
        typingHandle?.cancel()
        typingHandle = nil
        timeline = nil
        room = nil
        items = []
        messages = []
        typingUserIDs = []
    }

    func send(_ markdown: String) async throws {
        guard let timeline else { return }
        _ = try await timeline.send(msg: messageEventContentFromMarkdown(md: markdown))
        setTyping(false)
    }

    /// Announces our own typing state; the SDK debounces repeat calls.
    func setTyping(_ isTyping: Bool) {
        guard let room else { return }
        Task { try? await room.typingNotice(isTyping: isTyping) }
    }

    func paginateBackwards() async {
        guard let timeline, !isBackPaginating else { return }
        isBackPaginating = true
        _ = try? await timeline.paginateBackwards(numEvents: 50)
        isBackPaginating = false
    }

    func markAsRead() async {
        _ = try? await timeline?.markAsRead(receiptType: .read)
    }

    private func apply(_ diffs: [TimelineDiff]) {
        for diff in diffs {
            switch diff {
            case .append(let values): items.append(contentsOf: values)
            case .clear: items.removeAll()
            case .pushFront(let item): items.insert(item, at: 0)
            case .pushBack(let item): items.append(item)
            case .popFront: if !items.isEmpty { items.removeFirst() }
            case .popBack: if !items.isEmpty { items.removeLast() }
            case .insert(let index, let item): items.insert(item, at: Int(index))
            case .set(let index, let item): items[Int(index)] = item
            case .remove(let index): items.remove(at: Int(index))
            case .truncate(let length): items.removeSubrange(Int(length)..<items.count)
            case .reset(let values): items = values
            }
        }
        messages = items.compactMap(Self.message(from:))
    }

    /// Maps an SDK timeline item to a renderable message; nil for non-message
    /// items (day dividers, state events, reactions-only items…).
    static func message(from item: TimelineItem) -> ChatMessage? {
        guard let event = item.asEvent() else { return nil }
        guard case .msgLike(let msgLike) = event.content,
              case .message(let message) = msgLike.kind else { return nil }

        let eventID: String?
        if case .eventId(let id) = event.eventOrTransactionId {
            eventID = id
        } else {
            eventID = nil
        }

        return ChatMessage(id: item.uniqueId().id,
                           eventID: eventID,
                           sender: event.sender,
                           isOwn: event.isOwn,
                           text: message.body,
                           isEdited: message.isEdited,
                           timestamp: Date(timeIntervalSince1970: TimeInterval(event.timestamp) / 1000))
    }
}

/// Bridges the SDK's callback protocol to a closure.
private final class TimelineListenerProxy: TimelineListener {
    private let onUpdateClosure: ([TimelineDiff]) -> Void

    init(onUpdate: @escaping ([TimelineDiff]) -> Void) {
        onUpdateClosure = onUpdate
    }

    func onUpdate(diff: [TimelineDiff]) {
        onUpdateClosure(diff)
    }
}

private final class TypingListenerProxy: TypingNotificationsListener {
    private let onCall: ([String]) -> Void

    init(onCall: @escaping ([String]) -> Void) {
        self.onCall = onCall
    }

    func call(typingUserIds: [String]) {
        onCall(typingUserIds)
    }
}
