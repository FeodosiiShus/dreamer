import AppKit
import SwiftUI
import WebKit

struct MarkdownPreviewWebView: NSViewRepresentable {
    let bodyHTML: String
    let baseURL: URL?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.underPageBackgroundColor = NSColor(srgbRed: 25 / 255, green: 26 / 255, blue: 28 / 255, alpha: 1)
        webView.allowsMagnification = false
        context.coordinator.show(bodyHTML, baseURL: baseURL, in: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.show(bodyHTML, baseURL: baseURL, in: webView)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.navigationDelegate = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private var loadedBaseURL: URL?
        private var loadedBody: String?
        private var currentBody: String?
        private var isPageLoaded = false

        func show(_ body: String, baseURL: URL?, in webView: WKWebView) {
            currentBody = body
            if loadedBaseURL != baseURL || loadedBody == nil {
                load(body, baseURL: baseURL, in: webView)
                return
            }
            guard isPageLoaded, loadedBody != body else { return }
            apply(body, in: webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
            isPageLoaded = true
            guard let currentBody, currentBody != loadedBody else { return }
            apply(currentBody, in: webView)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            load(loadedBody ?? "", baseURL: loadedBaseURL, in: webView)
        }

        private func load(_ body: String, baseURL: URL?, in webView: WKWebView) {
            loadedBaseURL = baseURL
            loadedBody = body
            isPageLoaded = false
            let document = MarkdownHTMLRenderer.documentHTML(body: body, baseURL: baseURL)
            _ = webView.loadHTMLString(document, baseURL: baseURL)
        }

        private func apply(_ body: String, in webView: WKWebView) {
            loadedBody = body
            webView.evaluateJavaScript(Self.replaceBodyScript(body), completionHandler: { _, _ in })
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.navigationType == .linkActivated,
                  let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            if let fragment = url.fragment,
               let baseURL = loadedBaseURL,
               url.scheme == baseURL.scheme,
               url.path == baseURL.path {
                decisionHandler(.cancel)
                scroll(toAnchor: fragment, in: webView)
                return
            }

            decisionHandler(.cancel)
            _ = NSWorkspace.shared.open(url)
        }

        private func scroll(toAnchor fragment: String, in webView: WKWebView) {
            guard let literal = Self.javaScriptLiteral(fragment) else { return }
            webView.evaluateJavaScript(
                "(function(){var element = document.getElementById(\(literal));" +
                "if (element) { element.scrollIntoView(); }})();",
                completionHandler: { _, _ in }
            )
        }

        private static func replaceBodyScript(_ body: String) -> String {
            let literal = javaScriptLiteral(body) ?? "\"\""
            return "(function(){var y = window.scrollY;" +
                "document.body.innerHTML = \(literal);" +
                "window.scrollTo(0, y);})();"
        }

        private static func javaScriptLiteral(_ value: String) -> String? {
            guard let data = try? JSONEncoder().encode(value) else { return nil }
            return String(data: data, encoding: .utf8)
        }
    }
}
