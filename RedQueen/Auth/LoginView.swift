import SwiftUI
import CocoaLumberjackSwift

struct LoginView: View {
    @Environment(AppSession.self) private var appSession

    @State private var username = ""
    @State private var password = ""
    @State private var isLoggingIn = false
    @State private var errorMessage: String?

    @FocusState private var focusedField: Field?
    private enum Field { case username, password }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            BotAvatarView(size: 96)
                .padding(.bottom, 16)

            Text(AppConfig.agentDisplayName)
                .font(.largeTitle.bold())

            Text(AppConfig.homeserverURL.replacingOccurrences(of: "https://", with: ""))
                .font(.footnote)
                .foregroundStyle(Color.reMuted)
                .padding(.bottom, 40)

            VStack(spacing: 12) {
                TextField("Username", text: $username)
                    .textContentType(.username)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .focused($focusedField, equals: .username)
                    #if os(iOS)
                    .submitLabel(.next)
                    #endif
                    .onSubmit { focusedField = .password }
                    .padding(14)
                    .background(Color.reSurface, in: .rect(cornerRadius: 12))

                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .focused($focusedField, equals: .password)
                    #if os(iOS)
                    .submitLabel(.go)
                    #endif
                    .onSubmit { logIn() }
                    .padding(14)
                    .background(Color.reSurface, in: .rect(cornerRadius: 12))
            }
            .frame(maxWidth: 400)

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.top, 12)
            }

            Button(action: logIn) {
                Group {
                    if isLoggingIn {
                        ProgressView().tint(.white)
                    } else {
                        Text("Log In").bold()
                    }
                }
                .frame(maxWidth: 400)
                .padding(.vertical, 14)
                .background(canSubmit ? Color.reAccent : Color.reSurface, in: .rect(cornerRadius: 12))
                .foregroundStyle(.white)
            }
            .disabled(!canSubmit || isLoggingIn)
            .padding(.top, 20)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(REBackground())
        .onAppear {
            DDLogInfo("👁️ [LoginView] appeared")
            focusedField = .username
        }
    }

    private var canSubmit: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
    }

    private func logIn() {
        guard canSubmit, !isLoggingIn else { return }
        isLoggingIn = true
        errorMessage = nil
        Task {
            do {
                try await appSession.login(username: username.trimmingCharacters(in: .whitespaces),
                                           password: password)
            } catch {
                DDLogError("💥 [LoginView] logIn FAILED: \(error)")
                errorMessage = error.localizedDescription
            }
            isLoggingIn = false
        }
    }
}

#Preview {
    LoginView()
        .environment(AppSession())
}
