import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct LimiterCoverageTests {
    @MainActor
    private final class Recorder {
        var values: [Int] = []
    }

    private static let sleeperTimeout: Duration = .seconds(60)

    @Test
    func debounceRunsOnlyTheLastActionForAnIdentifier() async throws {
        let recorder = Recorder()
        let clock = TestClock()
        let id = UUID().uuidString

        Limiter.debounce(id: id, duration: 0.1, clock: clock) { recorder.values.append(1) }
        Limiter.debounce(id: id, duration: 0.1, clock: clock) { recorder.values.append(2) }
        Limiter.debounce(id: id, duration: 0.1, clock: clock) { recorder.values.append(3) }
        try await clock.waitForSleepers(1, timeout: Self.sleeperTimeout)
        #expect(clock.pendingSleeperCount == 1)

        clock.advance(by: .seconds(1))

        try await eventually { !recorder.values.isEmpty }
        #expect(recorder.values == [3])
        #expect(clock.pendingSleeperCount == 0)
    }

    @Test
    func debounceDelaysTheActionUntilTheDurationElapsed() async throws {
        let recorder = Recorder()
        let clock = TestClock()
        let id = UUID().uuidString

        Limiter.debounce(id: id, duration: 0.3, clock: clock) { recorder.values.append(1) }

        #expect(recorder.values.isEmpty)
        try await clock.waitForSleepers(1, timeout: Self.sleeperTimeout)
        clock.advance(by: .milliseconds(299))
        #expect(clock.pendingSleeperCount == 1)
        #expect(recorder.values.isEmpty)

        clock.advance(by: .milliseconds(1))

        try await eventually { !recorder.values.isEmpty }
        #expect(recorder.values == [1])
    }

    @Test
    func differentIdentifiersDebounceIndependently() async throws {
        let recorder = Recorder()
        let clock = TestClock()
        let first = UUID().uuidString
        let second = UUID().uuidString

        Limiter.debounce(id: first, duration: 0.1, clock: clock) { recorder.values.append(1) }
        Limiter.debounce(id: second, duration: 0.1, clock: clock) { recorder.values.append(2) }
        try await clock.waitForSleepers(2, timeout: Self.sleeperTimeout)

        clock.advance(by: .seconds(1))

        try await eventually { recorder.values.count == 2 }
        #expect(Set(recorder.values) == [1, 2])
    }

    @Test
    func identifierCanBeDebouncedAgainAfterFiring() async throws {
        let recorder = Recorder()
        let clock = TestClock()
        let id = UUID().uuidString

        Limiter.debounce(id: id, duration: 0.05, clock: clock) { recorder.values.append(1) }
        try await clock.waitForSleepers(1, timeout: Self.sleeperTimeout)
        clock.advance(by: .seconds(1))
        try await eventually { recorder.values == [1] }

        Limiter.debounce(id: id, duration: 0.05, clock: clock) { recorder.values.append(2) }
        try await clock.waitForSleepers(1, timeout: Self.sleeperTimeout)
        clock.advance(by: .seconds(1))
        try await eventually { recorder.values == [1, 2] }
    }

    @Test
    func debounceUsesTheContinuousClockByDefault() async throws {
        let recorder = Recorder()
        let id = UUID().uuidString

        Limiter.debounce(id: id, duration: 0.01) { recorder.values.append(1) }

        try await eventually { recorder.values == [1] }
    }
}
