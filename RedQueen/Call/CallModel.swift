import Foundation
import Observation
import MatrixRustSDK
import CocoaLumberjackSwift
#if os(iOS)
import AVFAudio
#endif

/// Drives one Element Call session: builds the widget, runs the SDK widget
/// driver, and pumps postMessage traffic between the driver and the webview.
@MainActor @Observable
final class CallModel {
    private(set) var widgetURL: URL?
    private(set) var errorMessage: String?
    /// Set when the widget reports the call ended (hangup/close).
    private(set) var isFinished = false

    /// Delivers driver→widget messages into the webview; set by the webview
    /// coordinator once the page exists. Messages arriving earlier are queued.
    var messageSink: ((String) -> Void)? {
        didSet {
            guard let messageSink else { return }
            for message in pendingMessages { messageSink(message) }
            pendingMessages.removeAll()
        }
    }

    private var pendingMessages: [String] = []
    private var handle: WidgetDriverHandle?
    private var driverTask: Task<Void, Never>?
    private var pumpTask: Task<Void, Never>?
    private let capabilitiesProvider = GrantAllCapabilitiesProvider()

    func start(room: Room, client: Client?, elementCallURL: String) async {
        guard let client else {
            errorMessage = "No active session."
            return
        }
        do {
            let properties = VirtualElementCallWidgetProperties(
                elementCallUrl: elementCallURL,
                widgetId: UUID().uuidString,
                parentUrl: nil,
                fontScale: nil,
                font: nil,
                encryption: AppConfig.encryptNewConversations ? .perParticipantKeys : .unencrypted,
                posthogUserId: nil,
                posthogApiHost: nil,
                posthogApiKey: nil,
                rageshakeSubmitUrl: nil,
                sentryDsn: nil,
                sentryEnvironment: nil)
            let config = VirtualElementCallWidgetConfig(intent: .startCall,
                                                        skipLobby: false,
                                                        hideHeader: true,
                                                        appPrompt: false)
            let settings = try newVirtualElementCallWidget(props: properties, config: config)

            let urlString = try await generateWebviewUrl(
                widgetSettings: settings,
                room: room,
                props: ClientProperties(clientId: "info.pich.redqueen",
                                        languageTag: Locale.current.identifier.replacingOccurrences(of: "_", with: "-"),
                                        theme: "dark"))
            guard let url = URL(string: urlString) else {
                errorMessage = "Element Call produced an invalid URL."
                return
            }

            let driverAndHandle = try makeWidgetDriver(settings: settings)
            handle = driverAndHandle.handle

            driverTask = Task { [capabilitiesProvider] in
                await driverAndHandle.driver.run(room: room, capabilitiesProvider: capabilitiesProvider)
            }
            pumpTask = Task { [weak self, handle = driverAndHandle.handle] in
                while let message = await handle.recv() {
                    guard !Task.isCancelled else { return }
                    await MainActor.run { self?.deliverToWidget(message) }
                }
            }

            configureAudioSession(active: true)
            widgetURL = url
        } catch {
            DDLogError("💥 [CallModel] start FAILED: \(error)")
            errorMessage = "Could not start call: \(error.localizedDescription)"
        }
    }

    /// Called by the webview bridge for widget→driver messages.
    func handleWidgetMessage(_ message: String) {
        if let data = message.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let action = json["action"] as? String,
           json["api"] as? String == "fromWidget",
           action == "io.element.close" || action == "im.vector.hangup" {
            isFinished = true
        }
        Task { [handle] in _ = await handle?.send(msg: message) }
    }

    func stop() {
        pumpTask?.cancel()
        driverTask?.cancel()
        pumpTask = nil
        driverTask = nil
        handle = nil
        messageSink = nil
        configureAudioSession(active: false)
    }

    private func deliverToWidget(_ message: String) {
        if let messageSink {
            messageSink(message)
        } else {
            pendingMessages.append(message)
        }
    }

    private func configureAudioSession(active: Bool) {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        if active {
            try? session.setCategory(.playAndRecord, mode: .videoChat,
                                     options: [.defaultToSpeaker, .allowBluetooth])
            try? session.setActive(true)
        } else {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
        }
        #endif
    }
}

/// Our own trusted Element Call deployment gets whatever it asks for.
private final class GrantAllCapabilitiesProvider: WidgetCapabilitiesProvider {
    func acquireCapabilities(capabilities: WidgetCapabilities) -> WidgetCapabilities {
        capabilities
    }
}
