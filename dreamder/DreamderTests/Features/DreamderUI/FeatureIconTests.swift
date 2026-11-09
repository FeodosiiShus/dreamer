import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct FeatureIconTests {
    private func snapshot(of icon: FeatureIcon) async throws -> NSBitmapImageRep {
        let hosted = HostedViewFixture.host(size: NSSize(width: 80, height: 80)) {
            icon.padding(10)
        }
        defer { hosted.close() }
        try await hosted.settle(.milliseconds(50))
        return try #require(hosted.snapshot())
    }

    @Test
    func systemAndBundledSymbolsRenderDifferentGlyphs() async throws {
        let system = try await snapshot(of: FeatureIcon(symbol: "star.fill", color: .red, size: 40))
        let bundled = try await snapshot(of: FeatureIcon(symbol: "vault", color: .red, size: 40))

        #expect(HostedView.pixelsDiffer(system, bundled))
    }

    @Test
    func symbolColorAndSizeChangeTheRendering() async throws {
        let defaults = try await snapshot(of: FeatureIcon(symbol: "star.fill"))
        let recolored = try await snapshot(of: FeatureIcon(symbol: "star.fill", color: .green))
        let larger = try await snapshot(of: FeatureIcon(symbol: "star.fill", size: 40))

        #expect(HostedView.pixelsDiffer(defaults, recolored))
        #expect(HostedView.pixelsDiffer(defaults, larger))
    }

    @Test
    func textIconUsesTheTextColorOrPrimary() async throws {
        let primary = try await snapshot(of: FeatureIcon(text: "A", color: .blue, size: 40))
        let custom = try await snapshot(of: FeatureIcon(text: "A", textColor: .yellow, color: .blue, size: 40))
        let defaults = try await snapshot(of: FeatureIcon(text: "A"))

        #expect(HostedView.pixelsDiffer(primary, custom))
        #expect(HostedView.pixelsDiffer(primary, defaults))
    }

    @Test
    func imageIconFillsTheRaisedIslandBackground() async throws {
        let image = try await snapshot(of: FeatureIcon(image: Image(systemName: "folder.fill"), size: 40))
        let defaults = try await snapshot(of: FeatureIcon(image: Image(systemName: "folder.fill")))
        let symbol = try await snapshot(of: FeatureIcon(symbol: "folder.fill", size: 40))

        #expect(HostedView.pixelsDiffer(image, defaults))
        #expect(HostedView.pixelsDiffer(image, symbol))
    }
}
