import Foundation
import Synchronization
import Testing
@testable import Dreamder

@Suite
struct FileEventBatcherTests {
    private final class Collector: Sendable {
        private let storage = Mutex<[[String]]>([])
        private let firstCall = Mutex(true)

        func record(_ events: [DirectoryEventStream.Event]) {
            storage.withLock { $0.append(events.map(\.path)) }
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

    private func waitUntil(_ condition: () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(30))
        while !condition(), clock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test
    func burstsInsideOneWindowArriveAsASingleOrderedBatch() async throws {
        let collector = Collector()
        let batcher = FileEventBatcher(window: .seconds(1)) { collector.record($0) }

        for index in 0..<500 {
            batcher.submit([event("f\(index)")])
        }

        try await waitUntil { !collector.batches.isEmpty }
        try await Task.sleep(for: .milliseconds(250))
        let batches = collector.batches
        #expect(batches.count == 1)
        #expect(batches.first == (0..<500).map { "/root/f\($0)" })
    }

    @Test
    func eventsArrivingWhileTheHandlerRunsFormTheNextBatch() async throws {
        let collector = Collector()
        let batcher = FileEventBatcher(window: .milliseconds(30)) { events in
            collector.record(events)
            if collector.consumeFirstCall() {
                try? await Task.sleep(for: .milliseconds(200))
            }
        }

        batcher.submit([event("one")])
        try await waitUntil { collector.batches.count == 1 }
        batcher.submit([event("two")])
        batcher.submit([event("three")])
        try await waitUntil { collector.batches.count == 2 }

        #expect(collector.batches == [["/root/one"], ["/root/two", "/root/three"]])
    }

    @Test
    func laterBurstsStartANewWindowAfterTheBatcherWentIdle() async throws {
        let collector = Collector()
        let batcher = FileEventBatcher(window: .milliseconds(30)) { collector.record($0) }

        batcher.submit([event("a")])
        try await waitUntil { collector.batches.count == 1 }
        try await Task.sleep(for: .milliseconds(60))
        batcher.submit([event("b")])
        try await waitUntil { collector.batches.count == 2 }

        #expect(collector.batches == [["/root/a"], ["/root/b"]])
    }

    @Test
    func emptySubmissionsAreIgnored() async throws {
        let collector = Collector()
        let batcher = FileEventBatcher(window: .milliseconds(20)) { collector.record($0) }

        batcher.submit([])
        try await Task.sleep(for: .milliseconds(120))

        #expect(collector.batches.isEmpty)
    }

    @Test
    func cancelDropsPendingEventsAndRejectsLaterOnes() async throws {
        let collector = Collector()
        let batcher = FileEventBatcher(window: .milliseconds(60)) { collector.record($0) }

        batcher.submit([event("dropped")])
        batcher.cancel()
        batcher.submit([event("rejected")])
        try await Task.sleep(for: .milliseconds(250))

        #expect(collector.batches.isEmpty)
    }

    @Test
    func defaultWindowIsOneHundredMilliseconds() async throws {
        let collector = Collector()
        let batcher = FileEventBatcher { collector.record($0) }
        let clock = ContinuousClock()
        let start = clock.now

        batcher.submit([event("timed")])
        try await waitUntil { !collector.batches.isEmpty }

        #expect(clock.now - start >= .milliseconds(90))
    }
}
