import AppKit
import SwiftUI
import Testing
import WebKit
@testable import Dreamder

extension MarkdownPreviewWebViewCoverageTests {
    @Test
    func navigationsThatAreNotLinkClicksAreCancelledWhenNoLoadIsPending() {
        let harness = MarkdownPreviewWebViewCoverageHarness()
        defer { harness.close() }
        let target = URL(string: "https://example.com/page")

        harness.decide(MarkdownPreviewWebViewCoverageAction(url: target, type: .other))
        harness.decide(MarkdownPreviewWebViewCoverageAction(url: target, type: .reload))
        harness.decide(MarkdownPreviewWebViewCoverageAction(url: target, type: .formSubmitted))
        harness.decide(MarkdownPreviewWebViewCoverageAction(url: target, type: .formResubmitted))
        harness.decide(MarkdownPreviewWebViewCoverageAction(url: target, type: .backForward))
        harness.decide(MarkdownPreviewWebViewCoverageAction(url: nil, type: .linkActivated))

        #expect(harness.decisions.values == Array(repeating: .cancel, count: 6))
        #expect(harness.opened.urls.isEmpty)
        #expect(harness.opened.edited.isEmpty)
    }

    @Test
    func onlyTheFirstOtherNavigationOfEachLoadIsAllowed() {
        let harness = MarkdownPreviewWebViewCoverageHarness()
        defer { harness.close() }
        let detached = WKWebView(frame: .zero)
        let target = URL(string: "https://example.com/page")

        harness.coordinator.show(harness.representable(heading), in: detached)
        harness.decide(MarkdownPreviewWebViewCoverageAction(url: target, type: .reload))
        harness.decide(MarkdownPreviewWebViewCoverageAction(url: target, type: .other))
        harness.decide(MarkdownPreviewWebViewCoverageAction(url: target, type: .other))

        var light = MarkdownPreviewFixtures.darkPalette
        light.background = MarkdownPreviewFixtures.color("#FFFFFF")
        harness.coordinator.show(harness.representable(heading, palette: light), in: detached)
        harness.decide(MarkdownPreviewWebViewCoverageAction(url: target, type: .other))
        harness.decide(MarkdownPreviewWebViewCoverageAction(url: target, type: .other))

        #expect(harness.decisions.values == [.cancel, .allow, .cancel, .allow, .cancel])
    }

    @Test
    func embeddedMetaRefreshesAndFramesCannotNavigateThePreviewAway() async throws {
        let harness = MarkdownPreviewWebViewCoverageHarness()
        defer { harness.close() }
        let recorder = MarkdownPreviewWebViewCoverageRecorder(coordinator: harness.coordinator)
        harness.webView.navigationDelegate = recorder
        let refresh = "https://example.invalid/refresh"
        let frame = "https://example.invalid/frame"
        let hostile = """
        <p>Hello</p><meta http-equiv="refresh" content="0;url=\(refresh)"><iframe src="\(frame)"></iframe>
        """

        harness.show(hostile)

        try await eventually { recorder.cancelled(refresh) && recorder.cancelled(frame) }
        try await harness.waitForPage()
        #expect(await harness.evaluate("document.querySelector('p').textContent") == "Hello")
        #expect(harness.webView.url?.host() != "example.invalid")
        harness.webView.navigationDelegate = nil
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
            #expect(harness.opened.edited.isEmpty)
            try await eventually { await harness.evaluate("JSON.stringify(window.__anchors)") == "[\"intro\"]" }
        }
    }

    @Test
    func linksAreRoutedByTheirTargetAndNeverLaunchLocalFilesOrApps() throws {
        try withTempDir { directory in
            let harness = MarkdownPreviewWebViewCoverageHarness(workspaceRoot: directory)
            defer { harness.close() }
            let web = try #require(URL(string: "https://example.com/a"))
            let mail = try #require(URL(string: "mailto:someone@example.com"))
            let inside = directory.appending(path: "docs/a.md").standardizedFileURL
            let insideWithFragment = try #require(URL(string: inside.absoluteString + "#section"))
            let command = directory.deletingLastPathComponent().appending(path: "payload.command")
            let application = URL(fileURLWithPath: "/System/Applications/Calculator.app")
            let script = try #require(URL(string: "javascript:alert(1)"))
            let unhandled = try #require(URL(string: "dreamder-coverage-unhandled-scheme://nothing"))
            let links = [web, mail, inside, insideWithFragment, command, application, script, unhandled]

            for link in links {
                harness.decide(MarkdownPreviewWebViewCoverageAction(url: link, type: .linkActivated))
            }

            #expect(harness.decisions.values == Array(repeating: .cancel, count: links.count))
            #expect(harness.opened.urls == [web, mail])
            #expect(harness.opened.edited == [inside, inside])
        }
    }

    @Test
    func linksWithoutAWorkspaceAreNeverOpenedAsFiles() {
        let harness = MarkdownPreviewWebViewCoverageHarness()
        defer { harness.close() }
        let file = URL(fileURLWithPath: "/tmp/payload.command")

        harness.decide(MarkdownPreviewWebViewCoverageAction(url: file, type: .linkActivated))

        #expect(harness.decisions.values == [.cancel])
        #expect(harness.opened.urls.isEmpty)
        #expect(harness.opened.edited.isEmpty)
    }

    @Test
    func theRepresentablesCoordinatorUsesTheLinksOfTheLatestShow() throws {
        let representable = MarkdownPreviewWebView(
            bodyHTML: "",
            baseURL: nil,
            palette: MarkdownPreviewFixtures.darkPalette,
            followOffset: nil,
            links: inertLinks()
        )
        let coordinator = representable.makeCoordinator()
        let decisions = MarkdownPreviewWebViewCoverageDecisions()
        let web = try #require(URL(string: "https://example.com/a"))
        let recorded = MarkdownPreviewWebViewCoverageOpened()
        let replaced = MarkdownPreviewWebView(
            bodyHTML: "",
            baseURL: nil,
            palette: MarkdownPreviewFixtures.darkPalette,
            followOffset: nil,
            links: MarkdownPreviewLinks(
                workspaceRoot: nil,
                openExternal: { recorded.urls.append($0) },
                openInEditor: { recorded.edited.append($0) }
            )
        )
        let detached = WKWebView(frame: .zero)

        coordinator.show(replaced, in: detached)
        coordinator.webView(
            detached,
            decidePolicyFor: MarkdownPreviewWebViewCoverageAction(url: web, type: .linkActivated),
            decisionHandler: { decisions.values.append($0) }
        )

        #expect(decisions.values == [.cancel])
        #expect(recorded.urls == [web])
    }

    @Test
    func theRepresentableCreatesConfiguresUpdatesAndDismantlesItsWebView() async throws {
        let hosted = HostedViewFixture.host(size: NSSize(width: 600, height: 400)) {
            MarkdownPreviewWebView(
                bodyHTML: heading,
                baseURL: nil,
                palette: MarkdownPreviewFixtures.darkPalette,
                followOffset: nil,
                links: inertLinks()
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
                followOffset: 5,
                links: inertLinks()
            )
        )
        hosted.layout()
        try await eventually { await Self.text(of: webView) == "World" }

        hosted.hosting.rootView = AnyView(Color.clear)
        hosted.layout()
        try await eventually { webView.navigationDelegate == nil }
    }
}
