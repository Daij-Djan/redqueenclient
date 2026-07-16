import SwiftUI
import MatrixRustSDK

struct ChatView: View {
    let room: Room
    /// Sent on arrival — the home-screen composer flow.
    var initialMessage: String?

    @Environment(AppSession.self) private var appSession
    @State private var store = TimelineStore()
    @State private var draft = ""
    @State private var attachError: String?
    @State private var didSendInitialMessage = false
    /// Tracked via the bottom sentinel's lazy-container lifecycle; true while
    /// the user is at (or within the lazy buffer of) the end.
    @State private var isNearBottom = true

    private static let bottomID = "bottom-sentinel"

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        if store.isBackPaginating {
                            ProgressView()
                                .padding(.top, 8)
                        }
                        ForEach(store.messages) { message in
                            MessageBubble(message: message)
                        }
                        if !store.typingUserIDs.isEmpty {
                            TypingIndicatorView()
                                .transition(.opacity)
                        }
                        Color.clear
                            .frame(height: 1)
                            .id(Self.bottomID)
                            .onAppear { isNearBottom = true }
                            .onDisappear { isNearBottom = false }
                    }
                    .animation(.easeInOut(duration: 0.2), value: store.typingUserIDs.isEmpty)
                    .padding(.horizontal, 14)
                }
                .contentMargins(.vertical, 12, for: .scrollContent)
                .defaultScrollAnchor(.bottom)
                .scrollDismissesKeyboard(.interactively)
                .refreshable { await store.paginateBackwards() }

                if let attachError {
                    Text(attachError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                ComposerView(text: $draft) { send(proxy: proxy) }
            }
            .background(REBackground())
            .onChange(of: store.messages.count) { _, _ in
                // Stick to the bottom for our own messages, or whenever the
                // user hasn't scrolled up to read history.
                if store.messages.last?.isOwn == true || isNearBottom {
                    scrollToBottom(proxy)
                }
            }
            .onChange(of: store.typingUserIDs.isEmpty) { _, isEmpty in
                if !isEmpty && isNearBottom {
                    scrollToBottom(proxy)
                }
            }
        }
        .onChange(of: draft) { _, newValue in
            store.setTyping(!newValue.isEmpty)
        }
        .navigationTitle(room.displayName() ?? "Chat")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task(id: room.id()) {
            store.detach()
            do {
                try await store.attach(room: room, ownUserID: appSession.userID)
                await store.markAsRead()
                if let initialMessage, !didSendInitialMessage {
                    didSendInitialMessage = true
                    try await store.send(initialMessage)
                    await NewChatService.autoName(room: room, firstMessage: initialMessage)
                }
            } catch {
                attachError = "Could not load conversation: \(error.localizedDescription)"
            }
        }
        .onDisappear { store.detach() }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(Self.bottomID, anchor: .bottom)
        }
    }

    private func send(proxy: ScrollViewProxy) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        Task {
            do {
                try await store.send(text)
                scrollToBottom(proxy)
                // First message titles the conversation, ChatGPT-style.
                if room.displayName() == "New chat" {
                    await NewChatService.autoName(room: room, firstMessage: text)
                }
            } catch {
                attachError = "Send failed: \(error.localizedDescription)"
                draft = text
            }
        }
    }
}
