import Foundation
import Synchronization
import Testing
@testable import Dreamder

@Suite
struct FileEventBatcherTests {
    private final class Collector: Sendable {
        private let storage = Mutex<[[String]]>([])
        private let firstCall = Mutex(true)
        private let continuation: AsyncStream<[String]>.Continuation
        let arrivals: AsyncStream<[String]>

        init() {
            let pair = AsyncStream<[String]>.makeStream()
            arrivals = pair.stream
            continuation = pair.continuation
        }

        func record(_ events: [DirectoryEventStream.Event]) {
            let paths = events.map(\.path)
            storage.withLock { $0.append(paths) }
            continuation.yield(paths)
        }

        func consumeFirstCall() -> Bool {
            firstCall.withLock { isFirst in
                defer { isFirst = false }
                return isFirst
            }
        }

        var batches: [[String]] {
            storage.withLock { $0 }
        }
    }

    private func event(_ name: String) -> DirectoryEventStream.Event {
        DirectoryEventStream.Event(path: "/root/\(name)", eventType: .itemCreated)
    }

    private func waitForWindow(_ clock: TestClock) async throws {
        try await clock.waitForSleepers(1, timeout: .seconds(100))
    }

    @Test
    func burstsInsideOneWindowArriveAsASingleOrderedBatch() async throws {
        let clock = TestClock()
        let collector = Collector()
        var arrivals = collector.arrivals.makeAsyncIterator()
        let batcher = FileEventBatcher(window: .seconds(1), clock: clock) { collector.record($0) }

        for index in 0..<500 {
            batcher.submit([event("f\(index)")])
        }

        try await waitForWindow(clock)
        #expect(clock.pendingSleeperCount == 1)
        #expect(collector.batches.isEmpty)
        clock.advance(by: .seconds(1))
        let batch = await arrivals.next()

        #expect(batch == (0..<500).map { "/root/f\($0)" })
        #expect(collector.batches.count == 1)
    }

    @Test
    func eventsArrivingWhileTheHandlerRunsFormTheNextBatch() async throws {
        let clock = TestClock()
        let collector = Collector()
        var arrivals = collector.arrivals.makeAsyncIterator()
        let (gate, release) = AsyncStream<Void>.makeStream()
        defer { release.finish() }
        let batcher = FileEventBatcher(window: .milliseconds(30), clock: clock) { events in
            collector.record(events)
            if collector.consumeFirstCall() {
                for await _ in gate { break }
            }
        }

        batcher.submit([event("one")])
        try await waitForWindow(clock)
        clock.advance(by: .milliseconds(30))
        let first = await arrivals.next()
        #expect(clock.pendingSleeperCount == 0)
        batcher.submit([event("two")])
        batcher.submit([event("three")])
        #expect(clock.pendingSleeperCount == 0)
        release.yield()
        try await waitForWindow(clock)
        #expect(clock.pendingSleeperCount == 1)
        clock.advance(by: .milliseconds(30))
        let second = await arrivals.next()
        #expect(clock.pendingSleeperCount == 0)

        #expect(first == ["/root/one"])
        #expect(second == ["/root/two", "/root/three"])
        #expect(collector.batches.count == 2)
    }

    @Test
    func laterBurstsStartANewWindowAfterTheBatcherWentIdle() async throws {
        let clock = TestClock()
        let collector = Collector()
        var arrivals = collector.arrivals.makeAsyncIterator()
        let batcher = FileEventBatcher(window: .milliseconds(30), clock: clock) { collector.record($0) }

        batcher.submit([event("a")])
        try await waitForWindow(clock)
        clock.advance(by: .milliseconds(30))
        let first = await arrivals.next()
        clock.advance(by: .milliseconds(60))
        batcher.submit([event("b")])
        try await waitForWindow(clock)
        #expect(clock.pendingDeadlines == [clock.now.advanced(by: .milliseconds(30))])
        clock.advance(by: .milliseconds(30))
        let second = await arrivals.next()

        #expect(first == ["/root/a"])
        #expect(second == ["/root/b"])
        #expect(collector.batches.count == 2)
    }

    @Test
    func emptySubmissionsAreIgnored() async throws {
        let clock = TestClock()
        let collector = Collector()
        var arrivals = collector.arrivals.makeAsyncIterator()
        let batcher = FileEventBatcher(window: .milliseconds(20), clock: clock) { collector.record($0) }

        batcher.submit([])
        #expect(clock.pendingSleeperCount == 0)
        batcher.submit([event("real")])
        try await waitForWindow(clock)
        #expect(clock.pendingSleeperCount == 1)
        clock.advance(by: .milliseconds(20))
        let batch = await arrivals.next()

        #expect(batch == ["/root/real"])
        #expect(collector.batches.count == 1)
    }

    @Test
    func cancelDropsPendingEventsAndRejectsLaterOnes() async throws {
        let clock = TestClock()
        let collector = Collector()
        let batcher = FileEventBatcher(window: .milliseconds(60), clock: clock) { collector.record($0) }

        batcher.submit([event("dropped")])
        batcher.cancel()
        batcher.submit([event("rejected")])
        try await waitForWindow(clock)
        clock.advance(by: .milliseconds(60))
        try await Task.sleep(for: .milliseconds(100))

        #expect(collector.batches.isEmpty)
        #expect(clock.pendingSleeperCount == 0)
    }

    @Test
    func defaultWindowIsOneHundredMilliseconds() async throws {
        let clock = TestClock()
        let collector = Collector()
        var arrivals = collector.arrivals.makeAsyncIterator()
        let batcher = FileEventBatcher(clock: clock) { collector.record($0) }

        batcher.submit([event("timed")])
        try await waitForWindow(clock)
        #expect(clock.pendingDeadlines == [clock.now.advanced(by: .milliseconds(100))])
        clock.advance(by: .milliseconds(99))
        #expect(clock.pendingSleeperCount == 1)
        #expect(collector.batches.isEmpty)
        clock.advance(by: .milliseconds(1))
        let batch = await arrivals.next()

        #expect(batch == ["/root/timed"])
    }
}
