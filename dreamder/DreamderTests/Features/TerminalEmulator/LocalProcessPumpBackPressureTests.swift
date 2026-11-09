import Foundation
import Synchronization
import SwiftTerm
import Testing
@testable import Dreamder

nonisolated private final class ProducerProgress: Sendable {
    private let deliveredChunks = Mutex(0)
    private let finishedFlag = Mutex(false)

    func chunkDelivered() {
        deliveredChunks.withLock { $0 += 1 }
    }

    func finish() {
        finishedFlag.withLock { $0 = true }
    }

    var chunks: Int {
        deliveredChunks.withLock { $0 }
    }

    var finished: Bool {
        finishedFlag.withLock { $0 }
    }
}

nonisolated private func makeBoundedPump(highWaterBytes: Int) -> LocalProcessPump {
    LocalProcessPump(
        highWaterBytes: highWaterBytes,
        windowSize: { winsize() },
        wake: { true }
    )
}

nonisolated private func produceChunks(
    count: Int,
    size: Int,
    into pump: LocalProcessPump,
    progress: ProducerProgress
) {
    pump.queue.async {
        for index in 0..<count {
            pump.dataReceived(slice: Array(repeating: UInt8(index), count: size)[...])
            progress.chunkDelivered()
        }
        progress.finish()
    }
}

@MainActor
@Suite(.uiGate)
struct LocalProcessPumpBackPressureTests {
    @Test
    func theDefaultLimitIsFinite() {
        #expect(LocalProcessPump.defaultHighWaterBytes == 256 * 1024)
    }

    @Test
    func aProducerBlocksOnceThePendingBytesReachTheLimit() async throws {
        let pump = makeBoundedPump(highWaterBytes: 20)
        let progress = ProducerProgress()

        produceChunks(count: 5, size: 10, into: pump, progress: progress)

        try await eventually(timeout: .seconds(20)) { progress.chunks == 2 }
        try await Task.sleep(for: .milliseconds(150))
        #expect(progress.chunks == 2)
        #expect(!progress.finished)
        #expect(pump.pendingByteCount == 20)
    }

    @Test
    func aProducerBelowTheLimitNeverBlocks() async throws {
        let pump = makeBoundedPump(highWaterBytes: 21)
        let progress = ProducerProgress()

        produceChunks(count: 2, size: 10, into: pump, progress: progress)

        try await eventually(timeout: .seconds(20)) { progress.finished }
        #expect(pump.pendingByteCount == 20)
    }

    @Test
    func drainingReleasesTheProducerAndKeepsEveryChunkInOrder() async throws {
        let pump = makeBoundedPump(highWaterBytes: 20)
        let progress = ProducerProgress()
        var received: [LocalProcessPump.Event] = []

        produceChunks(count: 7, size: 10, into: pump, progress: progress)

        try await eventually(timeout: .seconds(20)) {
            received.append(contentsOf: pump.takeEvents())
            return progress.finished
        }
        received.append(contentsOf: pump.takeEvents())

        let expected = (0..<7).map { LocalProcessPump.Event.data(Array(repeating: UInt8($0), count: 10)) }
        #expect(received == expected)
        #expect(pump.pendingByteCount == 0)
    }

    @Test
    func pendingBytesAreNeverFarAboveTheLimit() async throws {
        let pump = makeBoundedPump(highWaterBytes: 30)
        let progress = ProducerProgress()
        var highestPending = 0

        produceChunks(count: 40, size: 10, into: pump, progress: progress)

        try await eventually(timeout: .seconds(20)) {
            highestPending = max(highestPending, pump.pendingByteCount)
            _ = pump.takeEvents()
            return progress.finished
        }

        #expect(highestPending <= 30)
    }

    @Test
    func closingTheConsumerReleasesABlockedProducerAndDropsEverything() async throws {
        let pump = makeBoundedPump(highWaterBytes: 10)
        let progress = ProducerProgress()
        produceChunks(count: 4, size: 10, into: pump, progress: progress)
        try await eventually(timeout: .seconds(20)) { progress.chunks == 1 }
        try await Task.sleep(for: .milliseconds(100))
        #expect(!progress.finished)

        pump.close()

        try await eventually(timeout: .seconds(20)) { progress.finished }
        #expect(progress.chunks == 4)
        #expect(pump.takeEvents().isEmpty)
        #expect(pump.pendingByteCount == 0)
    }

    @Test
    func exitEventsNeverWaitForTheConsumer() async throws {
        let pump = makeBoundedPump(highWaterBytes: 10)
        let process = LocalProcess(delegate: pump)
        pump.dataReceived(slice: Array(repeating: 1, count: 10)[...])

        pump.queue.sync { pump.processTerminated(process, exitCode: 256) }

        #expect(pump.takeEvents() == [.data(Array(repeating: 1, count: 10)), .terminated(256)])
    }

    @Test
    func closingAnIdlePumpIsSafe() {
        let pump = makeBoundedPump(highWaterBytes: 10)
        pump.dataReceived(slice: [1, 2, 3][...])

        pump.close()
        pump.close()

        #expect(pump.takeEvents().isEmpty)
        #expect(pump.pendingByteCount == 0)
    }
}
