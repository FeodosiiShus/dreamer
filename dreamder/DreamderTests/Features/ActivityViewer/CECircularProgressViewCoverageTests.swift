import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct CECircularProgressViewCoverageTests {
    @Test
    func rendersTheTrackAndTheSpinningArc() async throws {
        let hosted = HostedViewFixture.host(size: NSSize(width: 40, height: 40)) {
            CECircularProgressView()
                .frame(width: 22, height: 22)
        }
        defer { hosted.close() }

        try await hosted.settle(.milliseconds(100))

        #expect(hosted.renders())
    }
}
