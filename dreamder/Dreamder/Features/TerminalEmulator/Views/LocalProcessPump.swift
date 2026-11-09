import Foundation
import Synchronization
import SwiftTerm

nonisolated final class LocalProcessPump: LocalProcessDelegate, Sendable {
    enum Event: Sendable, Equatable {
        case data([UInt8])
        case terminated(Int32?)
    }

    let queue = DispatchQueue(label: "dev.dreamder.LocalProcessPump", qos: .userInitiated)

    private let pending = Mutex<[Event]>([])
    private let windowSize: @Sendable () -> winsize
    private let wake: @Sendable () -> Void

    init(windowSize: @escaping @Sendable () -> winsize, wake: @escaping @Sendable () -> Void) {
        self.windowSize = windowSize
        self.wake = wake
    }

    func dataReceived(slice: ArraySlice<UInt8>) {
        append(.data(Array(slice)))
    }

    func processTerminated(_ source: LocalProcess, exitCode: Int32?) {
        append(.terminated(exitCode))
    }

    func getWindowSize() -> winsize {
        windowSize()
    }

    func takeEvents() -> [Event] {
        pending.withLock { events in
            let taken = events
            events.removeAll()
            return taken
        }
    }

    private func append(_ event: Event) {
        let wasEmpty = pending.withLock { events in
            events.append(event)
            return events.count == 1
        }
        if wasEmpty {
            wake()
        }
    }
}
