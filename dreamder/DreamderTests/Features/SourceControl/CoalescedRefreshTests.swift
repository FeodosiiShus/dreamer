import Foundation
import Testing
@testable import Dreamder

@Suite
struct CoalescedRefreshTests {
    private final class Probe: @unchecked Sendable {
        private let lock = NSLock()
        private var dirty = false
        private var runCount = 0
        private var lastRunSawDirty = false

        func markDirty() {
            lock.withLock { dirty = true }
        }

        func begin() {
            lock.withLock {
                runCount += 1
                lastRunSawDirty = dirty
            }
        }

        var runs: Int { lock.withLock { runCount } }
        var sawDirty: Bool { lock.withLock { lastRunSawDirty } }
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
}
