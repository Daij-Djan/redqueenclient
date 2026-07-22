import SwiftUI
import MatrixRustSDK

/// Where a navigation push lands: a chat, optionally with a message to send
/// on arrival (the Gemini-style home composer flow).
struct ChatDestination: Hashable {
    let roomID: String
    var initialMessage: String?
    var initialRecording: VoiceRecorder.Recording?
    var initialImages: [ImageProcessor.Processed] = []
}

/// Cold start shows the home composer once; afterwards the root is the
/// conversation list. Chats push onto the stack, so back always lands on
/// the list.
struct MainView: View {
    @Environment(AppSession.self) private var appSession
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("agentUserID") private var agentUserIDOverride = ""
    @AppStorage("pushGatewayURL") private var pushGatewayURL = AppConfig.defaultPushGatewayURL
    @AppStorage("showIDs") private var showIDs = false

    @State private var pushManager = PushManager.shared

    @State private var conversationList = ConversationListStore()
    @State private var path: [ChatDestination] = []
    @State private var isShowingHome = true
    @State private var isShowingSettings = false
    @State private var isCreatingChat = false
    @State private var errorMessage: String?
    @State private var conversationToDelete: Conversation?

    private var agentUserID: String {
        let trimmed = agentUserIDOverride.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? AppConfig.defaultAgentUserID(ownUserID: appSession.userID) : trimmed
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if isShowingHome {
                    HomeView(isCreating: isCreatingChat,
                             onSubmit: { text, images in
                                 startChat(sending: text.isEmpty ? nil : text, images: images)
                             },
                             onSubmitVoice: { startChat(sending: nil, recording: $0) },
                             onShowConversations: { isShowingHome = false })
                } else {
                    conversationListView
                }
            }
            .navigationDestination(for: ChatDestination.self) { destination in
                if let room = resolveRoom(destination.roomID) {
                    ChatView(room: room,
                             initialMessage: destination.initialMessage,
                             initialRecording: destination.initialRecording,
                             initialImages: destination.initialImages)
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
            if let client = appSession.client {
                await pushManager.start(client: client, gatewayURL: pushGatewayURL)
            }
        }
        .onChange(of: pushManager.pendingRoomID) { _, roomID in
            guard let roomID else { return }
            pushManager.pendingRoomID = nil
            isShowingHome = false
            path = [ChatDestination(roomID: roomID)]
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                conversationList.resyncBadge()
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(conversationList: conversationList)
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
                    conversationRow(conversation, icon: "bubble.left")
                }
            }
            .listRowBackground(Color.reSurface.opacity(0.55))

            if !conversationList.otherRooms.isEmpty {
                Section("Other rooms") {
                    ForEach(conversationList.otherRooms) { conversation in
                        conversationRow(conversation, icon: "number")
                    }
                }
                .listRowBackground(Color.reSurface.opacity(0.55))
            }
        }
        .scrollContentBackground(.hidden)
        .background(REBackground())
        .confirmationDialog("Delete “\(conversationToDelete?.displayName ?? "")”?",
                            isPresented: .init(
                                get: { conversationToDelete != nil },
                                set: { if !$0 { conversationToDelete = nil } }
                            ),
                            titleVisibility: .visible) {
            Button("Delete Conversation", role: .destructive) {
                if let conversationToDelete {
                    delete(conversationToDelete)
                }
            }
        } message: {
            Text("Leaves the room and removes it from your account. This cannot be undone.")
        }
        .overlay {
            if conversationList.conversations.isEmpty && conversationList.otherRooms.isEmpty {
                ContentUnavailableView {
                    BotAvatarView(size: 64)
                } description: {
                    Text("No conversations yet — start one with the compose button.")
                }
            }
        }
        .navigationTitle(AppConfig.agentDisplayName)
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

    private func conversationRow(_ conversation: Conversation, icon: String) -> some View {
        NavigationLink(value: ChatDestination(roomID: conversation.id)) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Label(conversation.displayName, systemImage: icon)
                        .lineLimit(1)
                        .fontWeight(conversation.unreadCount > 0 ? .semibold : .regular)
                    if showIDs {
                        Text(conversation.id)
                            .font(.caption2)
                            .foregroundStyle(Color.reMuted)
                            .lineLimit(1)
                    }
                }
                if conversation.unreadCount > 0 {
                    Spacer()
                    UnreadBadge(count: conversation.unreadCount)
                }
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                conversationToDelete = conversation
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    /// "Deleting" a Matrix room = leave it, then forget it; the room list's
    /// nonLeft filter drops it from the UI once the leave syncs.
    private func delete(_ conversation: Conversation) {
        guard let room = resolveRoom(conversation.id) else {
            errorMessage = "Room not found."
            return
        }
        Task {
            do {
                try await room.leave()
                try? await room.forget()
            } catch {
                errorMessage = "Could not delete conversation: \(error.localizedDescription)"
            }
        }
    }

    private func resolveRoom(_ roomID: String) -> Room? {
        if let room = conversationList.room(withID: roomID) { return room }
        return try? appSession.client?.getRoom(roomId: roomID)
    }

    private func startChat(sending message: String?,
                           recording: VoiceRecorder.Recording? = nil,
                           images: [ImageProcessor.Processed] = []) {
        guard let client = appSession.client, !isCreatingChat else { return }
        isCreatingChat = true
        Task {
            do {
                let room = try await NewChatService.createConversationRoom(client: client,
                                                                           agentUserID: agentUserID)
                conversationList.refreshMembership(roomID: room.id())
                isShowingHome = false
                path.append(ChatDestination(roomID: room.id(),
                                            initialMessage: message,
                                            initialRecording: recording,
                                            initialImages: images))
            } catch {
                errorMessage = "Could not create chat: \(error.localizedDescription)"
            }
            isCreatingChat = false
        }
    }
}
