import Foundation
import Testing
@testable import Dreamder

@MainActor
private final class DrainSource {
    var isOpen = true
    var receivedBytes = 0
    private(set) var sleeps: [Duration] = []

    func recordSleep(_ interval: Duration, then action: (Int) -> Void = { _ in }) {
        sleeps.append(interval)
        action(sleeps.count)
    }
}

@MainActor
@Suite(.serialized, .uiGate)
struct ActiveTaskTerminalDrainTests {
    private let interval = Duration.milliseconds(7)

    private func drain(
        _ source: DrainSource,
        stallRounds: Int,
        onSleep: @escaping (Int) -> Void = { _ in }
    ) async {
        await CEActiveTaskTerminalView.waitForEndOfOutput(
            isOpen: { source.isOpen },
            receivedBytes: { source.receivedBytes },
            interval: interval,
            stallRounds: stallRounds,
            sleep: { source.recordSleep($0, then: onSleep) }
        )
    }

    @Test
    func aClosedSourceNeedsNoWaiting() async {
        let source = DrainSource()
        source.isOpen = false

        await drain(source, stallRounds: 5)

        #expect(source.sleeps.isEmpty)
    }

    @Test
    func anOpenSilentSourceIsGivenExactlyTheStallRoundsBeforeWaitingStops() async {
        let source = DrainSource()

        await drain(source, stallRounds: 3)

        #expect(source.sleeps == [interval, interval, interval])
    }

    @Test
    func receivedBytesResetTheStallCount() async {
        let source = DrainSource()

        await drain(source, stallRounds: 3) { round in
            if round <= 2 {
                source.receivedBytes += 10
            }
        }

        #expect(source.sleeps.count == 5)
    }

    @Test
    func waitingStopsAsSoonAsTheSourceClosesMidWay() async {
        let source = DrainSource()

        await drain(source, stallRounds: 50) { round in
            if round == 2 {
                source.isOpen = false
            }
        }

        #expect(source.sleeps.count == 2)
    }

    @Test
    func noStallRoundsMeansNoWaitingAtAll() async {
        let source = DrainSource()

        await drain(source, stallRounds: 0)

        #expect(source.sleeps.isEmpty)
    }

    @Test
    func theDefaultSleepWaitsOneIntervalPerSilentRound() async {
        let clock = ContinuousClock()
        let start = clock.now
        var reads = 0

        await CEActiveTaskTerminalView.waitForEndOfOutput(
            isOpen: { true },
            receivedBytes: {
                reads += 1
                return 0
            },
            interval: .milliseconds(5),
            stallRounds: 2
        )

        #expect(reads == 3)
        #expect(clock.now - start >= .milliseconds(10))
    }
}
