import SwiftUI
import PhotosUI
import MatrixRustSDK
import CocoaLumberjackSwift

struct ChatView: View {
    let room: Room
    /// Sent on arrival — the home-screen composer flow.
    var initialMessage: String?
    var initialRecording: VoiceRecorder.Recording?
    var initialImages: [ImageProcessor.Processed] = []

    @Environment(AppSession.self) private var appSession
    @State private var store = TimelineStore()
    @State private var draft = ""
    @State private var attachError: String?
    @State private var didSendInitialMessage = false
    @State private var isShowingCall = false
    @State private var recorder = VoiceRecorder()
    @State private var audioPlayer = AudioPlayerService()
    @State private var imageLoader = ImageLoaderService()
    @State private var pendingImages: [PendingImage] = []
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var isShowingPhotoPicker = false
    @State private var isShowingCamera = false
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
                #if os(iOS)
                .scrollDismissesKeyboard(.interactively)
                #endif
                .refreshable { await store.paginateBackwards() }

                if let attachError {
                    Text(attachError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                ComposerView(text: $draft,
                             onSend: { send(proxy: proxy) },
                             recorder: recorder,
                             onSendVoice: { sendVoice($0, proxy: proxy) },
                             pendingImages: $pendingImages,
                             onPickLibrary: { isShowingPhotoPicker = true },
                             onPickCamera: cameraAvailable ? { isShowingCamera = true } : nil)
            }
            .background(REBackground())
            .environment(audioPlayer)
            .environment(imageLoader)
            .onChange(of: store.messages.count) { old, new in
                DDLogDebug("🟠 [ChatView] messages.count changed \(old) -> \(new)")
                // Stick to the bottom for our own messages, or whenever the
                // user hasn't scrolled up to read history.
                if store.messages.last?.isOwn == true || isNearBottom {
                    scrollToBottom(proxy)
                }
                // The room is on-screen, so any new message just arrived
                // straight into view — keep the read receipt current instead
                // of letting it (and the badge) drift while we're right here.
                Task { await store.markAsRead() }
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
        .photosPicker(isPresented: $isShowingPhotoPicker,
                      selection: $photoSelection,
                      maxSelectionCount: 6,
                      matching: .images)
        .onChange(of: photoSelection) { _, items in
            guard !items.isEmpty else { return }
            photoSelection = []
            Task {
                for item in items {
                    guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
                    stageImage(data: data)
                }
            }
        }
        #if os(iOS)
        .sheet(isPresented: $isShowingCamera) {
            CameraPicker { data in
                stageImage(data: data)
            }
            .ignoresSafeArea()
        }
        #endif
        .navigationTitle(room.displayName() ?? "Chat")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isShowingCall = true
                } label: {
                    Image(systemName: "phone.fill")
                }
                .accessibilityLabel("Voice call")
            }
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $isShowingCall) {
            CallScreen(room: room)
        }
        #else
        .sheet(isPresented: $isShowingCall) {
            CallScreen(room: room)
        }
        #endif
        .task(id: room.id()) {
            DDLogInfo("🟠 [ChatView] .task START for room \(room.id())")
            store.detach()
            audioPlayer.client = appSession.client
            imageLoader.client = appSession.client
            do {
                try await store.attach(room: room, ownUserID: appSession.userID)
                await store.markAsRead()
                if !didSendInitialMessage {
                    if !initialImages.isEmpty {
                        didSendInitialMessage = true
                        // Text (if any) rides along as the first image's caption.
                        for (index, image) in initialImages.enumerated() {
                            try store.sendImage(image, caption: index == 0 ? initialMessage : nil)
                        }
                        await NewChatService.autoName(room: room, firstMessage: initialMessage ?? "Image")
                    } else if let initialMessage {
                        didSendInitialMessage = true
                        try await store.send(initialMessage)
                        await NewChatService.autoName(room: room, firstMessage: initialMessage)
                    } else if let initialRecording {
                        didSendInitialMessage = true
                        try store.sendVoiceMessage(initialRecording)
                        await NewChatService.autoName(room: room, firstMessage: "Voice message")
                    }
                }
            } catch {
                attachError = "Could not load conversation: \(error.localizedDescription)"
                DDLogError("🟠 [ChatView] .task attach FAILED: \(error)")
            }
            DDLogInfo("🟠 [ChatView] .task END for room \(room.id())")
        }
        .onAppear {
            DDLogInfo("🟠 [ChatView] onAppear room \(room.id())")
            PushManager.shared.activeRoomID = room.id()
        }
        .onDisappear {
            DDLogInfo("🟠 [ChatView] onDisappear room \(room.id())")
            if PushManager.shared.activeRoomID == room.id() {
                PushManager.shared.activeRoomID = nil
            }
            _ = recorder.stop(discard: true)
            audioPlayer.stop()
            store.detach()
        }
    }

    private var cameraAvailable: Bool {
        #if os(iOS)
        CameraPicker.isAvailable
        #else
        false
        #endif
    }

    private func stageImage(data: Data) {
        guard let processed = try? ImageProcessor.processForUpload(data: data) else {
            DDLogError("💥 [ChatView] stageImage FAILED: could not decode/process image data")
            attachError = "Could not read that image."
            return
        }
        pendingImages.append(PendingImage(processed: processed,
                                          preview: ImageProcessor.previewImage(fileURL: processed.fileURL)))
    }

    private func sendVoice(_ recording: VoiceRecorder.Recording, proxy: ScrollViewProxy) {
        do {
            try store.sendVoiceMessage(recording)
            scrollToBottom(proxy)
        } catch {
            DDLogError("💥 [ChatView] sendVoice FAILED: \(error)")
            attachError = "Voice message failed: \(error.localizedDescription)"
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(Self.bottomID, anchor: .bottom)
        }
    }

    private func send(proxy: ScrollViewProxy) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let images = pendingImages
        guard !text.isEmpty || !images.isEmpty else { return }
        draft = ""
        pendingImages = []
        Task {
            do {
                if images.isEmpty {
                    try await store.send(text)
                } else {
                    // Composer text rides along as the first image's caption.
                    for (index, image) in images.enumerated() {
                        try store.sendImage(image.processed,
                                            caption: index == 0 && !text.isEmpty ? text : nil)
                    }
                }
                scrollToBottom(proxy)
                // First message titles the conversation, ChatGPT-style.
                if room.displayName() == "New chat" {
                    await NewChatService.autoName(room: room,
                                                  firstMessage: text.isEmpty ? "Image" : text)
                }
            } catch {
                DDLogError("💥 [ChatView] send FAILED: \(error)")
                attachError = "Send failed: \(error.localizedDescription)"
                draft = text
                pendingImages = images
            }
        }
    }
}
