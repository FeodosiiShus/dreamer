import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct IslandsColumnLayoutTests {
    private func input(
        left: Bool = true,
        bottom: Bool = true,
        maximized: Bool = false
    ) -> IslandsLayoutMetrics.Input {
        IslandsLayoutMetrics.Input(
            hasLeft: left,
            leftWidth: 240,
            hasBottom: bottom,
            bottomHeight: 200,
            bottomMaximized: maximized
        )
    }

    private func place(
        _ input: IslandsLayoutMetrics.Input,
        metrics: IslandsLayoutMetrics,
        probe: IslandsLayoutProbe?
    ) async throws -> HostedView {
        let hosted = HostedViewFixture.host(size: NSSize(width: 800, height: 600)) {
            IslandsColumnLayout(metrics: metrics, input: input, probe: probe) {
                Color.red.islandSlot(.left)
                Color.blue.islandSlot(.leftDivider)
                Color.green.islandSlot(.editor)
                Color.gray.islandSlot(.bottomDivider)
                Color.orange.islandSlot(.bottom)
            }
        }
        try await hosted.settle(.milliseconds(50))
        return hosted
    }

    @Test
    func theLayoutPlacesEverySlotAtTheFramesOfTheMetrics() async throws {
        for metrics in [IslandsLayoutMetrics.compact, IslandsLayoutMetrics.regular] {
            for state in [input(), input(left: false), input(bottom: false), input(left: false, bottom: false)] {
                let probe = IslandsLayoutProbe()
                let hosted = try await place(state, metrics: metrics, probe: probe)
                defer { hosted.close() }

                #expect(probe.area.width > 0)
                #expect(probe.area.height > 0)
                #expect(probe.frames == metrics.frames(in: probe.area, input: state))
                for island in probe.frames.islands {
                    #expect(island.minX >= metrics.gap)
                    #expect(island.minY >= metrics.gap)
                    #expect(island.maxX <= probe.area.width - metrics.gap)
                    #expect(island.maxY <= probe.area.height - metrics.gap)
                }
            }
        }
    }

    @Test
    func aMaximizedBottomWindowIsTheOnlyIslandAndKeepsTheGap() async throws {
        let metrics = IslandsLayoutMetrics.compact
        let probe = IslandsLayoutProbe()
        let hosted = try await place(input(maximized: true), metrics: metrics, probe: probe)
        defer { hosted.close() }

        #expect(probe.frames.islands == [probe.frames.bottom])
        #expect(probe.frames.bottom.minX == metrics.gap)
        #expect(probe.frames.bottom.maxX == probe.area.width - metrics.gap)
        #expect(probe.frames.bottom.minY == metrics.gap)
        #expect(probe.frames.bottom.maxY == probe.area.height - metrics.gap)
    }

    @Test
    func theLayoutRendersWithoutAProbe() async throws {
        let hosted = try await place(input(), metrics: .regular, probe: nil)
        defer { hosted.close() }

        #expect(hosted.renders())
    }

    @Test
    func anUnspecifiedProposalMeasuresAsZeroAndPlacesIntoAnEmptyArea() async throws {
        let probe = IslandsLayoutProbe()
        let state = input()
        let hosted = HostedViewFixture.host(size: NSSize(width: 200, height: 200)) {
            ZStack {
                Color.red
                IslandsColumnLayout(metrics: .compact, input: state, probe: probe) {
                    Color.green.islandSlot(.editor)
                }
                .fixedSize()
            }
        }
        defer { hosted.close() }
        try await hosted.settle(.milliseconds(50))

        #expect(probe.area == .zero)
        #expect(hosted.renders())
    }

    @Test
    func theProbeStartsEmpty() {
        let probe = IslandsLayoutProbe()

        #expect(probe.area == .zero)
        #expect(probe.frames == IslandsLayoutMetrics.Frames())
    }
}
