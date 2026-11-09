import Foundation
import Synchronization
import SwiftTerm
import Testing
@testable import Dreamder

nonisolated private final class PumpWakeCounter: Sendable {
    private let count = Mutex(0)

    func increment() {
        count.withLock { $0 += 1 }
    }

    var value: Int {
        count.withLock { $0 }
    }
}

nonisolated private func makePump(
    counter: PumpWakeCounter,
    rows: UInt16 = 24
) -> LocalProcessPump {
    LocalProcessPump(
        windowSize: { winsize(ws_row: rows, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0) },
        wake: { counter.increment() }
    )
}

@concurrent
private func deliverLinesLikeAShell(to pump: LocalProcessPump, lines: Int) async {
    let process = LocalProcess(delegate: pump)
    for index in 1...lines {
        pump.queue.sync {
            pump.dataReceived(slice: Array("line-\(index)\n".utf8)[...])
        }
    }
    pump.queue.sync {
        pump.processTerminated(process, exitCode: 0)
    }
}

@MainActor
private final class WeakTerminalViewBox {
    weak var view: CELocalShellTerminalView?
}

@MainActor
private func pumpOutlivingItsView() -> (pump: LocalProcessPump, box: WeakTerminalViewBox) {
    let box = WeakTerminalViewBox()
    let pump = autoreleasepool { () -> LocalProcessPump in
        let view = terminalCoverageView()
        box.view = view
        return view.processPump
    }
    return (pump, box)
}

@MainActor
@Suite(.uiGate)
struct LocalProcessPumpTests {
    @Test
    func eventsAreKeptInArrivalOrderAndWakeTheConsumerOncePerBatch() {
        let counter = PumpWakeCounter()
        let pump = makePump(counter: counter)
        let process = LocalProcess(delegate: pump)

        pump.dataReceived(slice: [1, 2][...])
        pump.dataReceived(slice: [3][...])
        pump.processTerminated(process, exitCode: 0)

        #expect(counter.value == 1)
        #expect(pump.takeEvents() == [.data([1, 2]), .data([3]), .terminated(0)])
        #expect(pump.takeEvents().isEmpty)

        pump.dataReceived(slice: [4][...])
        #expect(counter.value == 2)
        #expect(pump.takeEvents() == [.data([4])])
    }

    @Test
    func theWindowSizeComesFromTheProvider() {
        let pump = makePump(counter: PumpWakeCounter(), rows: 7)

        #expect(pump.getWindowSize().ws_row == 7)
        #expect(pump.getWindowSize().ws_col == 80)
    }

    @Test
    func outputDeliveredOffTheMainThreadIsBufferedWithoutTheMainThreadReading() async {
        let counter = PumpWakeCounter()
        let pump = makePump(counter: counter)

        await deliverLinesLikeAShell(to: pump, lines: 200)

        #expect(counter.value == 1)
        let events = pump.takeEvents()
        #expect(events.count == 201)
        #expect(events.first == .data(Array("line-1\n".utf8)))
        #expect(events.dropLast().last == .data(Array("line-200\n".utf8)))
        #expect(events.last == .terminated(0))
    }

    @Test
    func aTerminalViewDrainsBufferedOutputAndExitInOrder() {
        let view = terminalCoverageView()
        let delegate = TerminalCoverageDelegate()
        view.processDelegate = delegate

        view.processPump.dataReceived(slice: Array("from-the-pump".utf8)[...])
        view.processPump.processTerminated(view.process, exitCode: 3)
        view.drainProcessEvents()

        #expect(terminalCoverageText(view).contains("from-the-pump"))
        #expect(delegate.exitCodes == [3])
        #expect(view.processPump.takeEvents().isEmpty)
    }

    @Test
    func aPumpOutlivingItsViewReportsAnEmptyWindowAndStillBuffersOutput() async throws {
        let (pump, box) = pumpOutlivingItsView()
        try await eventually { box.view == nil }

        let size = pump.getWindowSize()
        pump.dataReceived(slice: [7, 8][...])

        #expect(size.ws_row == 0)
        #expect(size.ws_col == 0)
        #expect(pump.takeEvents() == [.data([7, 8])])
    }
}
