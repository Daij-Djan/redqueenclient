import SwiftUI
import MatrixRustSDK

/// Full-screen Element Call session for a room.
struct CallScreen: View {
    let room: Room

    @Environment(AppSession.self) private var appSession
    @Environment(\.dismiss) private var dismiss
    @AppStorage("elementCallURL") private var elementCallURL = AppConfig.defaultElementCallURL

    @State private var model = CallModel()

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()

            if let url = model.widgetURL {
                #if os(iOS)
                CallWebView(url: url, model: model)
                    .ignoresSafeArea(edges: .bottom)
                #endif
            } else if let errorMessage = model.errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "phone.down.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.red)
                    Text(errorMessage)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                VStack(spacing: 16) {
                    BotAvatarView(size: 96, glow: 2)
                    Text("Connecting…")
                        .foregroundStyle(Color.reMuted)
                    ProgressView()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.black.opacity(0.55), in: .circle)
            }
            .padding(.top, 8)
            .padding(.leading, 12)
            .accessibilityLabel("End call")
        }
        .task {
            await model.start(room: room, client: appSession.client, elementCallURL: elementCallURL)
        }
        .onChange(of: model.isFinished) { _, finished in
            if finished { dismiss() }
        }
        .onDisappear { model.stop() }
    }
}
