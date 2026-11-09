import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct BackgroundImageLayerTests {
    private func makeImage(color: NSColor = .red, side: CGFloat = 16) -> NSImage {
        NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            color.setFill()
            rect.fill()
            return true
        }
    }

    private func writePNG(to url: URL, color: NSColor = .red) throws {
        let tiff = try #require(makeImage(color: color).tiffRepresentation)
        let representation = try #require(NSBitmapImageRep(data: tiff))
        let png = try #require(representation.representation(using: .png, properties: [:]))
        try png.write(to: url)
    }

    private func hostLayer(image: NSImage?, fill: String?, defaults: UserDefaults) -> HostedView {
        if let fill {
            defaults.set(fill, forKey: Islands.BackgroundImageKey.fill)
        }
        return HostedViewFixture.host(size: NSSize(width: 120, height: 80)) {
            BackgroundImageLayer(image: image).defaultAppStorage(defaults)
        }
    }

    @Test
    func emptyPathLoadsNothing() {
        #expect(BackgroundImageLayer.loadImage(at: "") == nil)
    }

    @Test
    func missingFileLoadsNothing() throws {
        try withTempDir { directory in
            #expect(BackgroundImageLayer.loadImage(at: directory.appending(path: "missing.png").path) == nil)
        }
    }

    @Test
    func tildePathsAreExpandedBeforeCheckingReadability() {
        #expect(BackgroundImageLayer.loadImage(at: "~/.dreamder-missing-\(UUID().uuidString).png") == nil)
    }

    @Test
    func readableNonImageFileLoadsNothing() throws {
        try withTempDir { directory in
            let url = directory.appending(path: "notes.png")
            try "not an image".write(to: url, atomically: true, encoding: .utf8)

            #expect(BackgroundImageLayer.loadImage(at: url.path) == nil)
        }
    }

    @Test
    func readableImageFileLoads() throws {
        try withTempDir { directory in
            let url = directory.appending(path: "background.png")
            try writePNG(to: url)

            let image = try #require(BackgroundImageLayer.loadImage(at: url.path))

            #expect(image.size.width > 0)
            #expect(image.size.height > 0)
        }
    }

    @Test
    func everyFillModeRendersTheImage() async throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let image = makeImage()

        for fill in BackgroundImageFill.allCases.map(\.rawValue) {
            let hosted = hostLayer(image: image, fill: fill, defaults: defaults)
            defer { hosted.close() }
            try await hosted.settle(.milliseconds(50))

            #expect(hosted.renders(), "fill \(fill)")
        }
    }

    @Test
    func anUnknownFillValueFallsBackToFill() async throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let image = makeImage()

        let unknown = hostLayer(image: image, fill: "unknown", defaults: defaults)
        defer { unknown.close() }
        try await unknown.settle(.milliseconds(50))
        let filled = hostLayer(image: image, fill: BackgroundImageFill.fill.rawValue, defaults: defaults)
        defer { filled.close() }
        try await filled.settle(.milliseconds(50))

        #expect(!HostedView.pixelsDiffer(unknown.snapshot(), filled.snapshot()))
    }

    @Test
    func theDefaultFillIsUsedWhenNothingIsStored() async throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }

        let hosted = hostLayer(image: makeImage(), fill: nil, defaults: defaults)
        defer { hosted.close() }
        try await hosted.settle(.milliseconds(50))

        #expect(hosted.renders())
    }

    @Test
    func withoutAnImageNothingIsDrawn() async throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let empty = hostLayer(image: nil, fill: nil, defaults: defaults)
        defer { empty.close() }
        let drawn = hostLayer(image: makeImage(), fill: nil, defaults: defaults)
        defer { drawn.close() }
        try await empty.settle(.milliseconds(50))
        try await drawn.settle(.milliseconds(50))

        #expect(HostedView.pixelsDiffer(empty.snapshot(), drawn.snapshot()))
    }
}
