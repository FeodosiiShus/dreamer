import AppKit
import SwiftUI
import Testing
import WebKit
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct MarkdownPreviewWebViewCoverageTests {
    let heading = "<h1 md-src-pos=\"0..7\">Hello</h1>"
    let otherHeading = "<h1 md-src-pos=\"0..7\">World</h1>"

    static func text(of webView: WKWebView) async -> String? {
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
}
