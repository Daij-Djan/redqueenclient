import SwiftUI
import CocoaLumberjackSwift

struct SettingsView: View {
    let conversationList: ConversationListStore

    @Environment(AppSession.self) private var appSession
    @Environment(\.dismiss) private var dismiss
    @AppStorage("agentUserID") private var agentUserIDOverride = ""
    @AppStorage("elementCallURL") private var elementCallURL = AppConfig.defaultElementCallURL
    @AppStorage("pushGatewayURL") private var pushGatewayURL = AppConfig.defaultPushGatewayURL
    @AppStorage("showIDs") private var showIDs = false
    @AppStorage("debugLoggingEnabled") private var debugLoggingEnabled = true
    @State private var isShowingDeleteAllConfirmation = false
    @State private var isDeletingAll = false
    @State private var deleteAllError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    LabeledContent("User", value: appSession.userID ?? "—")
                    LabeledContent("Homeserver",
                                   value: AppConfig.homeserverURL.replacingOccurrences(of: "https://", with: ""))
                }

                Section {
                    TextField(AppConfig.defaultAgentUserID(ownUserID: appSession.userID),
                              text: $agentUserIDOverride)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                } header: {
                    Text("Agent")
                } footer: {
                    Text("Matrix user ID of the Hermes agent. New chats invite this user. Leave empty to use the default shown above — it must be on your homeserver, not a federated domain.")
                }

                Section {
                    TextField(AppConfig.defaultElementCallURL, text: $elementCallURL)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        #endif
                } header: {
                    Text("Voice & Video")
                } footer: {
                    Text("Element Call web app used for calls. The LiveKit backend comes from your homeserver's .well-known.")
                }

                Section {
                    TextField(AppConfig.defaultPushGatewayURL, text: $pushGatewayURL)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        #endif
                } header: {
                    Text("Push Notifications")
                } footer: {
                    Text("Sygnal push gateway notify endpoint. Takes effect at next launch.")
                }

                Section {
                    Toggle("Show IDs", isOn: $showIDs)
                } footer: {
                    Text("Shows the Matrix room ID under each conversation and the event ID under each message — useful for debugging.")
                }

                Section {
                    Toggle("Debug Logging", isOn: $debugLoggingEnabled)
                        .onChange(of: debugLoggingEnabled) { _, enabled in
                            AppLogger.setEnabled(enabled)
                        }
                } footer: {
                    Text("Writes a debug log to Documents/Logs — on macOS that's ~/Documents, on iOS it's visible in the Files app.")
                }

                Section {
                    Button(role: .destructive) {
                        isShowingDeleteAllConfirmation = true
                    } label: {
                        if isDeletingAll {
                            HStack {
                                ProgressView()
                                Text("Deleting…")
                            }
                        } else {
                            Text("Delete All Conversations")
                        }
                    }
                    .disabled(isDeletingAll)
                } footer: {
                    Text("Leaves and removes every conversation on the server. This cannot be undone.")
                }

                Section {
                    Button("Log Out", role: .destructive) {
                        Task {
                            await appSession.logout()
                            dismiss()
                        }
                    }
                }

                Section {
                    LabeledContent("SDK", value: String(AppConfig.sdkVersion.prefix(9)))
                } footer: {
                    Text("Matrix Rust SDK build")
                }
            }
            .scrollContentBackground(.hidden)
            .background(REBackground())
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Delete all conversations?",
                                isPresented: $isShowingDeleteAllConfirmation,
                                titleVisibility: .visible) {
                Button("Delete All Conversations", role: .destructive) {
                    Task {
                        isDeletingAll = true
                        let failures = await conversationList.deleteAllConversations()
                        isDeletingAll = false
                        if failures > 0 {
                            deleteAllError = "\(failures) conversation(s) could not be deleted."
                        }
                    }
                }
            } message: {
                Text("This leaves and removes every conversation on the server. This cannot be undone.")
            }
            .alert("Something went wrong", isPresented: .init(
                get: { deleteAllError != nil },
                set: { if !$0 { deleteAllError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteAllError ?? "")
            }
        }
        .onAppear {
            DDLogInfo("👁️ [SettingsView] appeared")
        }
    }
}
