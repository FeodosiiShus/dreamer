import AppKit
import SwiftUI
import Testing
import WebKit
@testable import Dreamder

@MainActor
private final class MarkdownPreviewWebViewCoverageOpened {
    var urls: [URL] = []
}

@MainActor
private final class MarkdownPreviewWebViewCoverageDecisions {
    var values: [WKNavigationActionPolicy] = []
}

@MainActor
private final class MarkdownPreviewWebViewCoverageAction: WKNavigationAction {
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
private final class MarkdownPreviewWebViewCoverageHarness {
    let opened: MarkdownPreviewWebViewCoverageOpened
    let decisions = MarkdownPreviewWebViewCoverageDecisions()
    let coordinator: MarkdownPreviewWebView.Coordinator
    let webView: WKWebView
    let window: NSWindow

    init() {
        let opened = MarkdownPreviewWebViewCoverageOpened()
        let coordinator = MarkdownPreviewWebView.Coordinator(openExternal: { opened.urls.append($0) })
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

    func show(
        _ body: String,
        baseURL: URL? = nil,
        palette: MarkdownPreviewPalette = MarkdownPreviewFixtures.darkPalette,
        followOffset: Int? = nil
    ) {
        coordinator.show(
            MarkdownPreviewWebView(bodyHTML: body, baseURL: baseURL, palette: palette, followOffset: followOffset),
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

@MainActor
@Suite(.serialized, .uiGate)
struct MarkdownPreviewWebViewCoverageTests {
    private let heading = "<h1 md-src-pos=\"0..7\">Hello</h1>"
    private let otherHeading = "<h1 md-src-pos=\"0..7\">World</h1>"

    private static func text(of webView: WKWebView) async -> String? {
        let value = try? await webView.evaluateJavaScript("document.body.innerText")
        return value as? String
    }

    @Test
    func theFirstShowLoadsTheDocumentWithThePaletteBackground() async throws {
        let harness = MarkdownPreviewWebViewCoverageHarness()
        defer { harness.close() }
        let palette = MarkdownPreviewFixtures.darkPalette

        harness.show(heading, palette: palette)

        try await eventually { await harness.bodyText() == "Hello" }
        try await harness.waitForPage()
        let pageColor: NSColor? = harness.webView.underPageBackgroundColor
        let background = try #require(pageColor?.usingColorSpace(.sRGB))
        #expect(Int((background.redComponent * 255).rounded()) == palette.background.red)
        #expect(Int((background.greenComponent * 255).rounded()) == palette.background.green)
        #expect(Int((background.blueComponent * 255).rounded()) == palette.background.blue)
    }

    @Test
    func aChangedBodyIsReplacedInPlaceWithoutReloadingThePage() async throws {
        let harness = MarkdownPreviewWebViewCoverageHarness()
        defer { harness.close() }
        harness.show(heading)
        try await harness.waitForPage()
        #expect(await harness.evaluate("window.__marker = 'kept'; 'ok'") == "ok")

        harness.show(otherHeading)

        try await eventually { await harness.bodyText() == "World" }
        #expect(await harness.evaluate("window.__marker") == "kept")
        harness.show(otherHeading)
        try await Task.sleep(for: .milliseconds(100))
        #expect(await harness.evaluate("window.__marker") == "kept")
    }

    @Test
    func aBodyShownWhileThePageIsStillLoadingIsAppliedWhenLoadingFinishes() async throws {
        let harness = MarkdownPreviewWebViewCoverageHarness()
        defer { harness.close() }

        harness.show(heading)
        harness.show(otherHeading)

        try await eventually { await harness.bodyText() == "World" }
        try await harness.waitForPage()
    }

    @Test
    func followOffsetsAreForwardedOncePerValue() async throws {
        let harness = MarkdownPreviewWebViewCoverageHarness()
        defer { harness.close() }
        harness.show(heading)
        try await harness.waitForPage()
        try await harness.installSpies()

        harness.show(heading, followOffset: 7)
        try await eventually { await harness.evaluate("JSON.stringify(window.__offsets)") == "[7]" }

        harness.show(heading, followOffset: 7)
        harness.show(heading, followOffset: nil)
        harness.show(heading, followOffset: 9)
        try await eventually { await harness.evaluate("JSON.stringify(window.__offsets)") == "[7,9]" }

        harness.show(otherHeading, followOffset: 9)
        try await eventually { await harness.bodyText() == "World" }
        #expect(await harness.evaluate("JSON.stringify(window.__offsets)") == "[7,9]")
    }

    @Test
    func theInitialFollowOffsetIsAppliedWhenTheDocumentFinishesLoading() async throws {
        let harness = MarkdownPreviewWebViewCoverageHarness()
        defer { harness.close() }

        harness.show(heading, followOffset: 3)

        try await eventually { await harness.bodyText() == "Hello" }
        try await harness.waitForPage()
    }

    @Test
    func aChangedPaletteOrBaseURLReloadsTheDocument() async throws {
        try await withTempDir { directory in
            let harness = MarkdownPreviewWebViewCoverageHarness()
            defer { harness.close() }
            harness.show(heading)
            try await harness.waitForPage()
            #expect(await harness.evaluate("window.__marker = 'old'; 'ok'") == "ok")

            var light = MarkdownPreviewFixtures.darkPalette
            light.background = MarkdownPreviewFixtures.color("#FFFFFF")
            harness.show(heading, palette: light)
            try await eventually { await harness.evaluate("typeof window.__marker") == "undefined" }
            try await harness.waitForPage()
            #expect(await harness.bodyText() == "Hello")
            #expect(await harness.evaluate("window.__marker = 'older'; 'ok'") == "ok")

            harness.show(heading, baseURL: directory, palette: light)
            try await eventually { await harness.evaluate("typeof window.__marker") == "undefined" }
            try await eventually { await harness.evaluate("document.baseURI") == directory.absoluteString }
        }
    }

    @Test
    func aTerminatedWebContentProcessIsReloadedWithTheLastShownDocument() async throws {
        let harness = MarkdownPreviewWebViewCoverageHarness()
        defer { harness.close() }
        harness.show(heading)
        try await harness.waitForPage()
        let mutated = await harness.evaluate("document.body.innerHTML = '<p>mutated</p>'; document.body.innerText")
        #expect(mutated == "mutated")

        harness.coordinator.webViewWebContentProcessDidTerminate(harness.webView)

        try await eventually { await harness.bodyText() == "Hello" }
    }

    @Test
    func aTerminationBeforeAnyDocumentWasShownLoadsNothing() {
        let harness = MarkdownPreviewWebViewCoverageHarness()
        defer { harness.close() }

        harness.coordinator.webViewWebContentProcessDidTerminate(harness.webView)

        #expect(harness.webView.isLoading == false)
        #expect(harness.webView.url == nil)
    }

    @Test
    func nonLinkNavigationsAndLinksWithoutURLsAreAllowed() {
        let harness = MarkdownPreviewWebViewCoverageHarness()
        defer { harness.close() }
        let target = URL(string: "https://example.com/page")

        harness.decide(MarkdownPreviewWebViewCoverageAction(url: target, type: .other))
        harness.decide(MarkdownPreviewWebViewCoverageAction(url: target, type: .reload))
        harness.decide(MarkdownPreviewWebViewCoverageAction(url: nil, type: .linkActivated))

        #expect(harness.decisions.values == [.allow, .allow, .allow])
        #expect(harness.opened.urls.isEmpty)
    }

    @Test
    func sameDocumentAnchorLinksScrollInsteadOfNavigating() async throws {
        try await withTempDir { directory in
            let harness = MarkdownPreviewWebViewCoverageHarness()
            defer { harness.close() }
            harness.show(heading, baseURL: directory)
            try await harness.waitForPage()
            try await harness.installSpies()
            let anchor = try #require(URL(string: "#intro", relativeTo: directory)?.absoluteURL)

            harness.decide(MarkdownPreviewWebViewCoverageAction(url: anchor, type: .linkActivated))

            #expect(harness.decisions.values == [.cancel])
            #expect(harness.opened.urls.isEmpty)
            try await eventually { await harness.evaluate("JSON.stringify(window.__anchors)") == "[\"intro\"]" }
        }
    }

    @Test
    func otherLinksOpenExternallyAndCancelTheNavigation() async throws {
        try withTempDir { directory in
            let harness = MarkdownPreviewWebViewCoverageHarness()
            defer { harness.close() }
            let web = try #require(URL(string: "https://example.com/a"))
            let withoutBase = try #require(URL(string: "file:///elsewhere/page.md#section"))

            harness.decide(MarkdownPreviewWebViewCoverageAction(url: withoutBase, type: .linkActivated))
            #expect(harness.opened.urls == [withoutBase])

            harness.show(heading, baseURL: directory)
            let otherPath = try #require(URL(string: "file:///elsewhere/page.md#section"))
            let otherScheme = try #require(URL(string: "https://example.com\(directory.path)#frag"))
            let noFragment = try #require(URL(string: "file://\(directory.path)"))

            harness.decide(MarkdownPreviewWebViewCoverageAction(url: web, type: .linkActivated))
            harness.decide(MarkdownPreviewWebViewCoverageAction(url: otherPath, type: .linkActivated))
            harness.decide(MarkdownPreviewWebViewCoverageAction(url: otherScheme, type: .linkActivated))
            harness.decide(MarkdownPreviewWebViewCoverageAction(url: noFragment, type: .linkActivated))

            #expect(harness.decisions.values == Array(repeating: .cancel, count: 5))
            #expect(harness.opened.urls == [withoutBase, web, otherPath, otherScheme, noFragment])
        }
    }

    @Test
    func theDefaultOpenerHandsTheURLToTheWorkspace() throws {
        let unhandled = try #require(URL(string: "dreamder-coverage-unhandled-scheme://nothing"))

        MarkdownPreviewWebView.Coordinator.openInWorkspace(unhandled)
    }

    @Test
    func theRepresentablesDefaultCoordinatorOpensExternalLinksThroughTheWorkspace() throws {
        let representable = MarkdownPreviewWebView(
            bodyHTML: "",
            baseURL: nil,
            palette: MarkdownPreviewFixtures.darkPalette,
            followOffset: nil
        )
        let coordinator = representable.makeCoordinator()
        let decisions = MarkdownPreviewWebViewCoverageDecisions()
        let unhandled = try #require(URL(string: "dreamder-coverage-unhandled-scheme://nothing"))

        coordinator.webView(
            WKWebView(frame: .zero),
            decidePolicyFor: MarkdownPreviewWebViewCoverageAction(url: unhandled, type: .linkActivated),
            decisionHandler: { decisions.values.append($0) }
        )

        #expect(decisions.values == [.cancel])
    }

    @Test
    func theRepresentableCreatesConfiguresUpdatesAndDismantlesItsWebView() async throws {
        let hosted = HostedViewFixture.host(size: NSSize(width: 600, height: 400)) {
            MarkdownPreviewWebView(
                bodyHTML: heading,
                baseURL: nil,
                palette: MarkdownPreviewFixtures.darkPalette,
                followOffset: nil
            )
        }
        defer { hosted.close() }
        try await eventually { hosted.views(of: WKWebView.self).first != nil }
        let webView = try #require(hosted.views(of: WKWebView.self).first)

        #expect(webView.navigationDelegate != nil)
        #expect(webView.allowsMagnification == false)
        #expect(webView.configuration.defaultWebpagePreferences.allowsContentJavaScript == false)
        try await eventually { await Self.text(of: webView) == "Hello" }

        hosted.hosting.rootView = AnyView(
            MarkdownPreviewWebView(
                bodyHTML: otherHeading,
                baseURL: nil,
                palette: MarkdownPreviewFixtures.darkPalette,
                followOffset: 5
            )
        )
        hosted.layout()
        try await eventually { await Self.text(of: webView) == "World" }

        hosted.hosting.rootView = AnyView(Color.clear)
        hosted.layout()
        try await eventually { webView.navigationDelegate == nil }
    }
}
