import Testing
@testable import Dreamder

@MainActor
@Suite
struct MainTurnCoalescerTests {
    @Test
    func burstOfRequestsRunsTheActionOnce() async {
        let signal = AsyncStream<Void>.makeStream()
        var runs = 0
        let coalescer = MainTurnCoalescer {
            runs += 1
            signal.continuation.yield()
        }

        for _ in 0..<5 {
            coalescer.request()
        }
        #expect(runs == 0)

        var iterator = signal.stream.makeAsyncIterator()
        await iterator.next()
        await Task.yield()
        await Task.yield()

        #expect(runs == 1)
    }

    @Test
    func requestAfterTheActionRanSchedulesANewRun() async {
        let signal = AsyncStream<Void>.makeStream()
        var runs = 0
        let coalescer = MainTurnCoalescer {
            runs += 1
            signal.continuation.yield()
        }
        var iterator = signal.stream.makeAsyncIterator()

        coalescer.request()
        await iterator.next()
        coalescer.request()
        coalescer.request()
        await iterator.next()
        await Task.yield()

        #expect(runs == 2)
    }

    @Test
    func releasedCoalescerDoesNotRunItsAction() async {
        var runs = 0
        var coalescer: MainTurnCoalescer? = MainTurnCoalescer { runs += 1 }

        coalescer?.request()
        coalescer = nil
        await Task.yield()
        await Task.yield()

        #expect(runs == 0)
    }
}
