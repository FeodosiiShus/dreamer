import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct CEContentUnavailableViewTests {
    private let size = NSSize(width: 320, height: 240)

    @Test func everyVariantRendersAndLooksDifferent() async throws {
        let bare = HostedViewFixture.host(size: size) {
            CEContentUnavailableView("No Selection")
        }
        defer { bare.close() }
        let described = HostedViewFixture.host(size: size) {
            CEContentUnavailableView(
                "No Results",
                description: "Nothing found in the project",
                systemImage: "exclamationmark.magnifyingglass"
            )
        }
        defer { described.close() }
        let withActions = HostedViewFixture.host(size: size) {
            CEContentUnavailableView("Failed", systemImage: "xmark.octagon.fill") {
                Button("Retry") {}
            }
        }
        defer { withActions.close() }

        try await bare.settle()
        try await described.settle()
        try await withActions.settle()

        #expect(bare.renders())
        #expect(described.renders())
        #expect(withActions.renders())
        #expect(HostedView.pixelsDiffer(bare.snapshot(), described.snapshot()))
        #expect(HostedView.pixelsDiffer(described.snapshot(), withActions.snapshot()))
    }

    @Test func descriptionWithoutImageStillRenders() async throws {
        let hosted = HostedViewFixture.host(size: size) {
            CEContentUnavailableView("Empty", description: "Nothing to show")
        }
        defer { hosted.close() }
        try await hosted.settle()
        #expect(hosted.renders())
    }
}
