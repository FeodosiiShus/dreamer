import Foundation
import Synchronization
import Testing
@testable import Dreamder

@Suite
struct CoalescedRefreshTests {
    private final class Probe: Sendable {
        private struct State {
            var dirty = false
            var runCount = 0
            var lastRunSawDirty = false
        }

        private let state = Mutex(State())

        func markDirty() {
            state.withLock { $0.dirty = true }
        }

        func begin() {
            state.withLock {
                $0.runCount += 1
                $0.lastRunSawDirty = $0.dirty
            }
        }

        var runs: Int { state.withLock { $0.runCount } }
        var sawDirty: Bool { state.withLock { $0.lastRunSawDirty } }
    }

    @Test
    func concurrentCallersShareRunsAndAlwaysSeeARunStartedAfterTheirRequest() async throws {
        let refresh = CoalescedRefresh()
        let probe = Probe()
        let work: @Sendable () async -> Void = {
            probe.begin()
            try? await Task.sleep(for: .milliseconds(100))
        }

        async let first: Void = refresh.run(work)
        try await Task.sleep(for: .milliseconds(20))
        probe.markDirty()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask { await refresh.run(work) }
            }
        }
        #expect(probe.sawDirty)
        await first
        #expect(probe.runs <= 2)

        await refresh.run(work)
        #expect(probe.runs <= 3)
        #expect(probe.runs >= 2)
    }

    @Test
    func debouncedRequestsInsideTheWindowShareOneRunStartedAfterTheDelay() async throws {
        let clock = TestClock()
        let refresh = CoalescedRefresh(clock: clock)
        let probe = Probe()
        let start = clock.now

        let callers = (0..<10).map { _ in
            Task { await refresh.run(debounce: .milliseconds(200)) { probe.begin() } }
        }
        try await waitUntil { await refresh.requestCount == 10 }
        try await clock.waitForSleepers(1, timeout: .seconds(100))
        #expect(clock.pendingDeadlines == [start.advanced(by: .milliseconds(200))])
        #expect(probe.runs == 0)
        clock.advance(by: .milliseconds(200))
        for caller in callers {
            await caller.value
        }

        #expect(probe.runs == 1)
    }

    @Test
    func anImmediateRequestCutsThePendingDebounceShort() async throws {
        let clock = TestClock()
        let refresh = CoalescedRefresh(clock: clock)
        let probe = Probe()
        let start = clock.now

        let debounced = Task { await refresh.run(debounce: .seconds(60)) { probe.begin() } }
        try await waitUntil { await refresh.requestCount == 1 }
        try await clock.waitForSleepers(1, timeout: .seconds(100))
        await refresh.run { probe.begin() }
        await debounced.value

        #expect(clock.now == start)
        #expect(clock.pendingSleeperCount == 0)
        #expect(probe.runs == 1)
    }

    @Test
    func debouncedRequestsNeverDelayAnImmediateOneThatIsAlreadyPending() async throws {
        let clock = TestClock()
        let refresh = CoalescedRefresh(clock: clock)
        let probe = Probe()
        let start = clock.now
        let (gate, release) = AsyncStream<Void>.makeStream()
        defer { release.finish() }
        let slowWork: @Sendable () async -> Void = {
            probe.begin()
            for await _ in gate { break }
        }

        let running = Task { await refresh.run(slowWork) }
        try await waitUntil { probe.runs == 1 }
        let immediate = Task { await refresh.run { probe.begin() } }
        try await waitUntil { await refresh.requestCount == 2 }
        let debounced = Task { await refresh.run(debounce: .seconds(60)) { probe.begin() } }
        try await waitUntil { await refresh.requestCount == 3 }
        release.yield()
        release.finish()
        await running.value
        await immediate.value
        await debounced.value

        #expect(clock.now == start)
        #expect(clock.pendingSleeperCount == 0)
        #expect(probe.runs == 2)
    }

    private func waitUntil(_ condition: () async -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(100))
        while await !condition(), clock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await condition())
    }
}
