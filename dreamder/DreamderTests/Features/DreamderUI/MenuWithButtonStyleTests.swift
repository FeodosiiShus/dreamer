import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct MenuWithButtonStyleTests {
    @Test
    func rendersTheButtonLookAroundTheMenu() async throws {
        let hosted = HostedViewFixture.host(size: NSSize(width: 120, height: 60)) {
            MenuWithButtonStyle(systemImage: "ellipsis") {
                Group {
                    Button("Import") {}
                    Button("Export") {}
                }
            }
        }
        defer { hosted.close() }

        try await hosted.settle(.milliseconds(100))

        #expect(hosted.renders())
    }

    @Test
    func differentSymbolsRenderDifferently() async throws {
        let ellipsis = HostedViewFixture.host(size: NSSize(width: 120, height: 60)) {
            MenuWithButtonStyle(systemImage: "ellipsis") { Button("Item") {} }
        }
        let plus = HostedViewFixture.host(size: NSSize(width: 120, height: 60)) {
            MenuWithButtonStyle(systemImage: "plus") { Button("Item") {} }
        }
        defer {
            ellipsis.close()
            plus.close()
        }
        try await ellipsis.settle(.milliseconds(100))
        try await plus.settle(.milliseconds(100))

        #expect(HostedView.pixelsDiffer(ellipsis.snapshot(), plus.snapshot()))
    }
}
