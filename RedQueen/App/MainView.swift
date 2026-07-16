import SwiftUI
import MatrixRustSDK

/// Where a navigation push lands: a chat, optionally with a message to send
/// on arrival (the Gemini-style home composer flow).
struct ChatDestination: Hashable {
    let roomID: String
    var initialMessage: String?
}

/// Cold start shows the home composer once; afterwards the root is the
/// conversation list. Chats push onto the stack, so back always lands on
/// the list.
struct MainView: View {
    @Environment(AppSession.self) private var appSession
    @AppStorage("agentUserID") private var agentUserIDOverride = ""

    @State private var conversationList = ConversationListStore()
    @State private var path: [ChatDestination] = []
    @State private var isShowingHome = true
    @State private var isShowingSettings = false
    @State private var isCreatingChat = false
    @State private var errorMessage: String?

    private var agentUserID: String {
        let trimmed = agentUserIDOverride.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? AppConfig.defaultAgentUserID(ownUserID: appSession.userID) : trimmed
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if isShowingHome {
                    HomeView(isCreating: isCreatingChat,
                             onSubmit: { startChat(sending: $0) },
                             onShowConversations: { isShowingHome = false })
                } else {
                    conversationListView
                }
            }
            .navigationDestination(for: ChatDestination.self) { destination in
                if let room = resolveRoom(destination.roomID) {
                    ChatView(room: room, initialMessage: destination.initialMessage)
                } else {
                    ContentUnavailableView("Conversation not found",
                                           systemImage: "bubble.left",
                                           description: Text("The room isn't available yet — try again in a moment."))
                }
            }
        }
        .task {
            guard let syncService = appSession.syncService else { return }
            do {
                try await conversationList.start(syncService: syncService, agentUserID: agentUserID)
            } catch {
                errorMessage = "Sync failed: \(error.localizedDescription)"
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
        }
        .alert("Something went wrong", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var conversationListView: some View {
        List {
            Section {
                ForEach(conversationList.conversations) { conversation in
                    NavigationLink(value: ChatDestination(roomID: conversation.id)) {
                        Label(conversation.displayName, systemImage: "bubble.left")
                            .lineLimit(1)
                    }
                }
            }

            if !conversationList.otherRooms.isEmpty {
                Section("Other rooms") {
                    ForEach(conversationList.otherRooms) { conversation in
                        NavigationLink(value: ChatDestination(roomID: conversation.id)) {
                            Label(conversation.displayName, systemImage: "number")
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .overlay {
            if conversationList.conversations.isEmpty && conversationList.otherRooms.isEmpty {
                ContentUnavailableView("No conversations yet",
                                       systemImage: "crown",
                                       description: Text("Start one with the compose button."))
            }
        }
        .navigationTitle("Red Queen")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { startChat(sending: nil) }) {
                    if isCreatingChat {
                        ProgressView()
                    } else {
                        Image(systemName: "square.and.pencil")
                    }
                }
                .disabled(isCreatingChat)
                .accessibilityLabel("New chat")
            }
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    isShowingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
        }
    }

    private func resolveRoom(_ roomID: String) -> Room? {
        if let room = conversationList.room(withID: roomID) { return room }
        return try? appSession.client?.getRoom(roomId: roomID)
    }

    private func startChat(sending message: String?) {
        guard let client = appSession.client, !isCreatingChat else { return }
        isCreatingChat = true
        Task {
            do {
                let room = try await NewChatService.createConversationRoom(client: client,
                                                                           agentUserID: agentUserID)
                conversationList.refreshMembership(roomID: room.id())
                isShowingHome = false
                path.append(ChatDestination(roomID: room.id(), initialMessage: message))
            } catch {
                errorMessage = "Could not create chat: \(error.localizedDescription)"
            }
            isCreatingChat = false
        }
    }
}
