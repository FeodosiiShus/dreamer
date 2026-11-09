import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct PressActionsTests {
    private func snapshot<Content: View>(of content: Content) async throws -> NSBitmapImageRep {
        let hosted = HostedViewFixture.host(size: NSSize(width: 120, height: 120)) { content }
        defer { hosted.close() }
        try await hosted.settle(.milliseconds(50))
        #expect(hosted.renders())
        return try #require(hosted.snapshot())
    }

    @Test
    func pressActionLeavesTheContentAppearanceUnchanged() async throws {
        let plain = try await snapshot(of: Color.blue)
        let withRelease = try await snapshot(of: Color.blue.pressAction(onPress: {}, onRelease: {}))
        let pressOnly = try await snapshot(of: Color.blue.pressAction(onPress: {}))

        #expect(HostedView.pixelsDiffer(plain, withRelease) == false)
        #expect(HostedView.pixelsDiffer(plain, pressOnly) == false)
    }
}
