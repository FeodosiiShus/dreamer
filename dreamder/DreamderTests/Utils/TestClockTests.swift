import Foundation
import Synchronization
import Testing

@Suite
struct TestClockTests {
    @Test
    func timeOnlyMovesWhenAdvanced() {
        let clock = TestClock()
        let start = clock.now
        #expect(clock.now == start)
        clock.advance(by: .seconds(3))
        #expect(start.duration(to: clock.now) == .seconds(3))
    }

    @Test
    func sleeperResumesOnlyAfterItsDeadline() async throws {
        let clock = TestClock()
        let finished = Flag()
        let sleeper = Task {
            try await clock.sleep(for: .seconds(10))
            finished.set()
        }
        try await clock.waitForSleepers()
        #expect(clock.pendingSleeperCount == 1)

        clock.advance(by: .seconds(9))
        #expect(clock.pendingSleeperCount == 1)
        #expect(finished.value == false)

        clock.advance(by: .seconds(1))
        try await sleeper.value
        #expect(finished.value)
        #expect(clock.pendingSleeperCount == 0)
    }

    @Test
    func sleepUntilAPastDeadlineReturnsImmediately() async throws {
        let clock = TestClock()
        clock.advance(by: .seconds(5))
        try await clock.sleep(until: TestClock.Instant(offset: .seconds(1)))
        #expect(clock.pendingSleeperCount == 0)
    }

    @Test
    func advancingResumesEveryDueSleeper() async throws {
        let clock = TestClock()
        let sleepers = (1...3).map { index in
            Task { try await clock.sleep(for: .seconds(index)) }
        }
        try await clock.waitForSleepers(3)
        #expect(clock.pendingDeadlines.map { TestClock.Instant(offset: .zero).duration(to: $0) }
            == [.seconds(1), .seconds(2), .seconds(3)])

        clock.advance(by: .seconds(2))
        try await sleepers[0].value
        try await sleepers[1].value
        #expect(clock.pendingSleeperCount == 1)

        clock.advance(by: .seconds(1))
        try await sleepers[2].value
        #expect(clock.pendingSleeperCount == 0)
    }

    @Test
    func cancellingASleeperThrowsAndUnregistersIt() async throws {
        let clock = TestClock()
        let sleeper = Task { try await clock.sleep(for: .seconds(60)) }
        try await clock.waitForSleepers()
        sleeper.cancel()
        await #expect(throws: CancellationError.self) {
            try await sleeper.value
        }
        #expect(clock.pendingSleeperCount == 0)
    }

    @Test
    func waitingForSleepersThatNeverComeTimesOut() async {
        let clock = TestClock()
        await #expect(throws: TestClock.WaitError.sleepersDidNotArrive(expected: 2, actual: 0)) {
            try await clock.waitForSleepers(2, timeout: .milliseconds(30))
        }
    }
}

private final class Flag: Sendable {
    private let storage = Mutex(false)

    var value: Bool { storage.withLock { $0 } }

    func set() { storage.withLock { $0 = true } }
}
