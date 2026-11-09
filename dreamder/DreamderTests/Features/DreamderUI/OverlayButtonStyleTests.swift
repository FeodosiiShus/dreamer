import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct OverlayButtonStyleTests {
    private func snapshot(colorScheme: ColorScheme) async throws -> NSBitmapImageRep {
        let hosted = HostedViewFixture.host(size: NSSize(width: 60, height: 60)) {
            Button(action: {}) { Image(systemName: "xmark") }
                .buttonStyle(.overlay)
                .environment(\.colorScheme, colorScheme)
        }
        defer { hosted.close() }
        try await hosted.settle(.milliseconds(50))
        #expect(hosted.renders())
        return try #require(hosted.snapshot())
    }

    @Test
    func overlayStyleRendersForBothColorSchemes() async throws {
        let dark = try await snapshot(colorScheme: .dark)
        let light = try await snapshot(colorScheme: .light)

        #expect(HostedView.pixelsDiffer(dark, light))
    }
}
