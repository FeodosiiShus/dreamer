import AppKit
import SwiftUI
import Testing
import WebKit
@testable import Dreamder

@MainActor
final class MarkdownPreviewWebViewCoverageOpened {
    var urls: [URL] = []
    var edited: [URL] = []
}

@MainActor
func inertLinks() -> MarkdownPreviewLinks {
    MarkdownPreviewLinks(workspaceRoot: nil, openExternal: { _ in }, openInEditor: { _ in })
}

@MainActor
final class MarkdownPreviewWebViewCoverageRecorder: NSObject, WKNavigationDelegate {
    struct Record {
        let url: URL?
        let policy: WKNavigationActionPolicy
    }

    private let coordinator: MarkdownPreviewWebView.Coordinator
    private(set) var records: [Record] = []

    init(coordinator: MarkdownPreviewWebView.Coordinator) {
        self.coordinator = coordinator
        super.init()
    }

    func cancelled(_ url: String) -> Bool {
        records.contains { $0.url?.absoluteString == url && $0.policy == .cancel }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        let url = navigationAction.request.url
        coordinator.webView(webView, decidePolicyFor: navigationAction) { [weak self] policy in
            self?.records.append(Record(url: url, policy: policy))
            decisionHandler(policy)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        coordinator.webView(webView, didFinish: navigation)
    }
}

@MainActor
final class MarkdownPreviewWebViewCoverageDecisions {
    var values: [WKNavigationActionPolicy] = []
}

@MainActor
final class MarkdownPreviewWebViewCoverageAction: WKNavigationAction {
    private let stubbedRequest: URLRequest
    private let stubbedType: WKNavigationType

    init(url: URL?, type: WKNavigationType) {
        var request = URLRequest(url: URL(fileURLWithPath: "/"))
        request.url = url
        stubbedRequest = request
        stubbedType = type
        super.init()
    }

    override var request: URLRequest {
        stubbedRequest
    }

    override var navigationType: WKNavigationType {
        stubbedType
    }
}

@MainActor
final class MarkdownPreviewWebViewCoverageHarness {
    let opened: MarkdownPreviewWebViewCoverageOpened
    let decisions = MarkdownPreviewWebViewCoverageDecisions()
    let coordinator: MarkdownPreviewWebView.Coordinator
    let webView: WKWebView
    let window: NSWindow

    init(workspaceRoot: URL? = nil) {
        let opened = MarkdownPreviewWebViewCoverageOpened()
        let coordinator = MarkdownPreviewWebView.Coordinator(
            links: MarkdownPreviewLinks(
                workspaceRoot: workspaceRoot,
                openExternal: { opened.urls.append($0) },
                openInEditor: { opened.edited.append($0) }
            )
        )
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 600, height: 400), configuration: configuration)
        webView.navigationDelegate = coordinator
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = webView
        window.orderFront(nil)
        self.opened = opened
        self.coordinator = coordinator
        self.webView = webView
        self.window = window
    }

    func close() {
        webView.navigationDelegate = nil
        window.close()
    }

    func representable(
        _ body: String,
        baseURL: URL? = nil,
        palette: MarkdownPreviewPalette = MarkdownPreviewFixtures.darkPalette,
        followOffset: Int? = nil
    ) -> MarkdownPreviewWebView {
        MarkdownPreviewWebView(
            bodyHTML: body,
            baseURL: baseURL,
            palette: palette,
            followOffset: followOffset,
            links: inertLinks()
        )
    }

    func show(
        _ body: String,
        baseURL: URL? = nil,
        palette: MarkdownPreviewPalette = MarkdownPreviewFixtures.darkPalette,
        followOffset: Int? = nil
    ) {
        coordinator.show(
            representable(body, baseURL: baseURL, palette: palette, followOffset: followOffset),
            in: webView
        )
    }

    func evaluate(_ script: String) async -> String? {
        let value = try? await webView.evaluateJavaScript(script)
        return value as? String
    }

    func bodyText() async -> String? {
        await evaluate("document.body.innerText")
    }

    func waitForPage() async throws {
        try await eventually { await evaluate("typeof window.dreamderPreview") == "object" }
    }

    func installSpies() async throws {
        let installed = await evaluate(
            """
            window.__offsets = [];
            window.__anchors = [];
            window.dreamderPreview.scrollToSourceOffset = function (offset) { window.__offsets.push(offset); };
            window.dreamderPreview.scrollToAnchor = function (identifier) { window.__anchors.push(identifier); };
            "installed";
            """
        )
        #expect(installed == "installed")
    }

    func decide(_ action: WKNavigationAction) {
        let decisions = decisions
        coordinator.webView(webView, decidePolicyFor: action, decisionHandler: { decisions.values.append($0) })
    }
}
