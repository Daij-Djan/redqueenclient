import SwiftUI

struct SettingsView: View {
    @Environment(AppSession.self) private var appSession
    @Environment(\.dismiss) private var dismiss
    @AppStorage("agentUserID") private var agentUserIDOverride = ""
    @AppStorage("elementCallURL") private var elementCallURL = AppConfig.defaultElementCallURL
    @AppStorage("pushGatewayURL") private var pushGatewayURL = AppConfig.defaultPushGatewayURL
    @AppStorage("showIDs") private var showIDs = false

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
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("Agent")
                } footer: {
                    Text("Matrix user ID of the Hermes agent. New chats invite this user. Leave empty to use the default shown above — it must be on your homeserver, not a federated domain.")
                }

                Section {
                    TextField(AppConfig.defaultElementCallURL, text: $elementCallURL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                } header: {
                    Text("Voice & Video")
                } footer: {
                    Text("Element Call web app used for calls. The LiveKit backend comes from your homeserver's .well-known.")
                }

                Section {
                    TextField(AppConfig.defaultPushGatewayURL, text: $pushGatewayURL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
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
        }
    }
}
