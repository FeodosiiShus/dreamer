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

    @Test
    func dragChangeFiresPressAndDragEndFiresReleaseWhenProvided() {
        let counter = PressCounter()
        let withRelease = PressActions(
            onPress: { counter.presses += 1 },
            onRelease: { counter.releases += 1 }
        )
        let pressOnly = PressActions(onPress: { counter.presses += 1 })

        withRelease.pressChanged(0)
        withRelease.pressEnded(0)
        pressOnly.pressChanged(0)
        pressOnly.pressEnded(0)

        #expect(counter.presses == 2)
        #expect(counter.releases == 1)
    }
}

@MainActor
private final class PressCounter {
    var presses = 0
    var releases = 0
}
