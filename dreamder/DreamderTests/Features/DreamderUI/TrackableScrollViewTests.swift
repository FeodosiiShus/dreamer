import AppKit
import Observation
import SwiftUI
import Testing
@testable import Dreamder

@Observable
@MainActor
final class TrackableScrollOffsets {
    static let unset: CGFloat = -1_000_000

    var leading: CGFloat = TrackableScrollOffsets.unset
    var trailing: CGFloat? = TrackableScrollOffsets.unset
}

@MainActor
struct TrackableScrollHarness: View {
    let offsets: TrackableScrollOffsets
    let axes: Axis.Set
    let tracksTrailing: Bool

    var body: some View {
        @Bindable var offsets = offsets
        TrackableScrollView(
            axes,
            showIndicators: false,
            contentOffset: $offsets.leading,
            contentTrailingOffset: tracksTrailing ? $offsets.trailing : nil
        ) {
            Color.blue.frame(
                width: axes == .vertical ? 50 : 2_000,
                height: axes == .vertical ? 2_000 : 50
            )
        }
    }
}

@MainActor
@Suite(.uiGate)
struct TrackableScrollViewTests {
    private let size = NSSize(width: 300, height: 300)

    @Test(arguments: [Axis.Set.vertical, Axis.Set.horizontal])
    func reportsLeadingAndTrailingOffsetsAlongTheScrollAxis(axes: Axis.Set) async throws {
        let offsets = TrackableScrollOffsets()
        let hosted = HostedViewFixture.host(size: size) {
            TrackableScrollHarness(offsets: offsets, axes: axes, tracksTrailing: true)
        }
        defer { hosted.close() }

        try await eventually(timeout: .seconds(30)) {
            offsets.leading != TrackableScrollOffsets.unset && offsets.trailing != TrackableScrollOffsets.unset
        }
        let trailing = try #require(offsets.trailing)
        #expect(trailing > 1_000)
    }

    @Test(arguments: [Axis.Set.vertical, Axis.Set.horizontal])
    func withoutATrailingBindingOnlyTheLeadingOffsetIsReported(axes: Axis.Set) async throws {
        let offsets = TrackableScrollOffsets()
        let hosted = HostedViewFixture.host(size: size) {
            TrackableScrollHarness(offsets: offsets, axes: axes, tracksTrailing: false)
        }
        defer { hosted.close() }

        try await eventually(timeout: .seconds(30)) { offsets.leading != TrackableScrollOffsets.unset }
        #expect(offsets.trailing == TrackableScrollOffsets.unset)
    }
}
