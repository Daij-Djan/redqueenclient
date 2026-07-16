import SwiftUI

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

            Image(systemName: "crown.fill")
                .font(.system(size: 56))
                .foregroundStyle(.red.gradient)
                .padding(.bottom, 16)

            Text("Red Queen")
                .font(.largeTitle.bold())

            Text(AppConfig.homeserverURL.replacingOccurrences(of: "https://", with: ""))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.bottom, 40)

            VStack(spacing: 12) {
                TextField("Username", text: $username)
                    .textContentType(.username)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($focusedField, equals: .username)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .password }
                    .padding(14)
                    .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))

                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .focused($focusedField, equals: .password)
                    .submitLabel(.go)
                    .onSubmit { logIn() }
                    .padding(14)
                    .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
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
                .background(canSubmit ? Color.red : Color.gray.opacity(0.4), in: .rect(cornerRadius: 12))
                .foregroundStyle(.white)
            }
            .disabled(!canSubmit || isLoggingIn)
            .padding(.top, 20)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 24)
        .onAppear { focusedField = .username }
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
