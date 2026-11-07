import AppKit
import SwiftUI
import WebKit

struct MarkdownPreviewWebView: NSViewRepresentable {
    let bodyHTML: String
    let baseURL: URL?
    let palette: MarkdownPreviewPalette
    let followOffset: Int?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsMagnification = false
        context.coordinator.show(self, in: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.show(self, in: webView)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.navigationDelegate = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private var loadedBaseURL: URL?
        private var loadedPalette: MarkdownPreviewPalette?
        private var loadedBody: String?
        private var currentBody: String?
        private var followOffset: Int?
        private var appliedFollowOffset: Int?
        private var isPageLoaded = false

        func show(_ view: MarkdownPreviewWebView, in webView: WKWebView) {
            currentBody = view.bodyHTML
            followOffset = view.followOffset
            if loadedBaseURL != view.baseURL || loadedPalette != view.palette || loadedBody == nil {
                load(view.bodyHTML, baseURL: view.baseURL, palette: view.palette, in: webView)
                return
            }
            guard isPageLoaded else { return }
            if loadedBody != view.bodyHTML {
                apply(view.bodyHTML, in: webView)
            }
            follow(in: webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
            isPageLoaded = true
            webView.evaluateJavaScript(MarkdownPreviewScripts.pageScript, completionHandler: { _, _ in })
            if let currentBody, currentBody != loadedBody {
                apply(currentBody, in: webView)
            }
            appliedFollowOffset = nil
            follow(in: webView)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            guard let loadedPalette else { return }
            load(loadedBody ?? "", baseURL: loadedBaseURL, palette: loadedPalette, in: webView)
        }

        private func load(_ body: String, baseURL: URL?, palette: MarkdownPreviewPalette, in webView: WKWebView) {
            loadedBaseURL = baseURL
            loadedPalette = palette
            loadedBody = body
            isPageLoaded = false
            appliedFollowOffset = nil
            webView.underPageBackgroundColor = palette.background.nsColor
            let document = MarkdownHTMLRenderer.documentHTML(body: body, baseURL: baseURL, palette: palette)
            _ = webView.loadHTMLString(document, baseURL: baseURL)
        }

        private func apply(_ body: String, in webView: WKWebView) {
            loadedBody = body
            let literal = Self.javaScriptLiteral(body) ?? "\"\""
            let script = MarkdownPreviewScripts.replaceBodyScript(bodyLiteral: literal, follow: followOffset != nil)
            webView.evaluateJavaScript(script, completionHandler: { _, _ in })
        }

        private func follow(in webView: WKWebView) {
            guard let followOffset, followOffset != appliedFollowOffset else { return }
            appliedFollowOffset = followOffset
            let script = MarkdownPreviewScripts.scrollScript(offset: followOffset)
            webView.evaluateJavaScript(script, completionHandler: { _, _ in })
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
                MarkdownPreviewScripts.anchorScript(identifierLiteral: literal),
                completionHandler: { _, _ in }
            )
        }

        private static func javaScriptLiteral(_ value: String) -> String? {
            guard let data = try? JSONEncoder().encode(value) else { return nil }
            return String(data: data, encoding: .utf8)
        }
    }
}
