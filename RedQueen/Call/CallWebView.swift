import SwiftUI
import WebKit

#if os(iOS)

/// Hosts the Element Call web app and bridges widget postMessages to the
/// SDK widget driver (via `CallModel`).
struct CallWebView: UIViewRepresentable {
    let url: URL
    let model: CallModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        // Forward messages the *widget* emits (fromWidget requests and
        // toWidget responses) to native. The driver's own injections echo on
        // the same window and are filtered out here.
        let bridgeScript = """
        window.addEventListener('message', (event) => {
            const data = event.data;
            if (!data || typeof data !== 'object') { return; }
            if ((data.api === 'fromWidget' && !('response' in data)) ||
                (data.api === 'toWidget' && ('response' in data))) {
                window.webkit.messageHandlers.\(Coordinator.handlerName).postMessage(JSON.stringify(data));
            }
        });
        """
        configuration.userContentController.addUserScript(
            WKUserScript(source: bridgeScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        configuration.userContentController.add(context.coordinator, name: Coordinator.handlerName)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.uiDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        context.coordinator.attach(webView: webView)
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.handlerName)
        coordinator.detach()
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKUIDelegate {
        static let handlerName = "redqueenCall"

        private let model: CallModel
        private weak var webView: WKWebView?

        init(model: CallModel) {
            self.model = model
        }

        func attach(webView: WKWebView) {
            self.webView = webView
            model.messageSink = { [weak webView] message in
                // The driver hands us a JSON string; replay it as a browser
                // postMessage so matrix-widget-api inside the page sees it.
                webView?.evaluateJavaScript("postMessage(\(message), '*')") { _, _ in }
            }
        }

        func detach() {
            model.messageSink = nil
        }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard let body = message.body as? String else { return }
            Task { @MainActor in
                model.handleWidgetMessage(body)
            }
        }

        func webView(_ webView: WKWebView,
                     requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                     initiatedByFrame frame: WKFrameInfo,
                     type: WKMediaCaptureType,
                     decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            decisionHandler(.grant)
        }
    }
}

#elseif os(macOS)

/// Hosts the Element Call web app and bridges widget postMessages to the
/// SDK widget driver (via `CallModel`) — same bridge as iOS, wrapped for AppKit.
struct CallWebView: NSViewRepresentable {
    let url: URL
    let model: CallModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let bridgeScript = """
        window.addEventListener('message', (event) => {
            const data = event.data;
            if (!data || typeof data !== 'object') { return; }
            if ((data.api === 'fromWidget' && !('response' in data)) ||
                (data.api === 'toWidget' && ('response' in data))) {
                window.webkit.messageHandlers.\(Coordinator.handlerName).postMessage(JSON.stringify(data));
            }
        });
        """
        configuration.userContentController.addUserScript(
            WKUserScript(source: bridgeScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        configuration.userContentController.add(context.coordinator, name: Coordinator.handlerName)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.uiDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.attach(webView: webView)
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.handlerName)
        coordinator.detach()
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKUIDelegate {
        static let handlerName = "redqueenCall"

        private let model: CallModel
        private weak var webView: WKWebView?

        init(model: CallModel) {
            self.model = model
        }

        func attach(webView: WKWebView) {
            self.webView = webView
            model.messageSink = { [weak webView] message in
                webView?.evaluateJavaScript("postMessage(\(message), '*')") { _, _ in }
            }
        }

        func detach() {
            model.messageSink = nil
        }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard let body = message.body as? String else { return }
            Task { @MainActor in
                model.handleWidgetMessage(body)
            }
        }

        func webView(_ webView: WKWebView,
                     requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                     initiatedByFrame frame: WKFrameInfo,
                     type: WKMediaCaptureType,
                     decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            decisionHandler(.grant)
        }
    }
}

#endif
