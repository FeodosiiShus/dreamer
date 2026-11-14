import Foundation
import Synchronization
import SwiftTerm

nonisolated final class LocalProcessPump: LocalProcessDelegate, Sendable {
    enum Event: Sendable, Equatable {
        case data([UInt8])
        case terminated(Int32?)
    }

    private nonisolated struct State: Sendable {
        var events: [Event] = []
        var byteCount = 0
        var producerWaiting = false
        var closed = false
    }

    static let defaultHighWaterBytes = 256 * 1024
    static let defaultReapAttempts = 250
    static let defaultReapInterval = DispatchTimeInterval.milliseconds(2)

    let queue = DispatchQueue(label: "dev.dreamder.LocalProcessPump", qos: .userInitiated)

    private let state = Mutex(State())
    private let drained = DispatchSemaphore(value: 0)
    private let highWaterBytes: Int
    private let reapAttempts: Int
    private let reapInterval: DispatchTimeInterval
    private let reap: @Sendable (pid_t) -> ChildReap
    private let windowSize: @Sendable () -> winsize
    private let wake: @Sendable () -> Bool

    init(
        highWaterBytes: Int = LocalProcessPump.defaultHighWaterBytes,
        reapAttempts: Int = LocalProcessPump.defaultReapAttempts,
        reapInterval: DispatchTimeInterval = LocalProcessPump.defaultReapInterval,
        reap: @escaping @Sendable (pid_t) -> ChildReap = ChildReap.nonBlocking,
        windowSize: @escaping @Sendable () -> winsize,
        wake: @escaping @Sendable () -> Bool
    ) {
        self.highWaterBytes = highWaterBytes
        self.reapAttempts = reapAttempts
        self.reapInterval = reapInterval
        self.reap = reap
        self.windowSize = windowSize
        self.wake = wake
    }

    var pendingByteCount: Int {
        state.withLock { $0.byteCount }
    }

    func dataReceived(slice: ArraySlice<UInt8>) {
        while mustWaitForConsumer() {
            drained.wait()
        }
        append(.data(Array(slice)), byteCount: slice.count)
    }

    func processTerminated(_ source: LocalProcess, exitCode: Int32?) {
        resolveTermination(of: source.shellPid, reported: exitCode, attemptsLeft: reapAttempts)
    }

    func resolveTermination(of processIdentifier: pid_t, reported: Int32?, attemptsLeft: Int) {
        guard processIdentifier > 0 else {
            append(.terminated(reported), byteCount: 0)
            return
        }
        switch reap(processIdentifier) {
        case .exited(let waitStatus):
            append(.terminated(waitStatus), byteCount: 0)
        case .pending where attemptsLeft > 0:
            queue.asyncAfter(deadline: .now() + reapInterval) { [weak self] in
                self?.resolveTermination(of: processIdentifier, reported: reported, attemptsLeft: attemptsLeft - 1)
            }
        case .pending, .unavailable:
            append(.terminated(reported), byteCount: 0)
        }
    }

    func getWindowSize() -> winsize {
        windowSize()
    }

    func takeEvents() -> [Event] {
        let (taken, producerWasWaiting) = state.withLock { state in
            let taken = state.events
            state.events.removeAll()
            state.byteCount = 0
            let waiting = state.producerWaiting
            state.producerWaiting = false
            return (taken, waiting)
        }
        if producerWasWaiting {
            drained.signal()
        }
        return taken
    }

    func close() {
        let producerWasWaiting = state.withLock { state in
            state.closed = true
            state.events.removeAll()
            state.byteCount = 0
            let waiting = state.producerWaiting
            state.producerWaiting = false
            return waiting
        }
        if producerWasWaiting {
            drained.signal()
        }
    }

    private func mustWaitForConsumer() -> Bool {
        state.withLock { state in
            let full = state.byteCount >= highWaterBytes && !state.closed
            state.producerWaiting = full
            return full
        }
    }

    private func append(_ event: Event, byteCount: Int) {
        let shouldWake = state.withLock { state in
            guard !state.closed else { return false }
            state.events.append(event)
            state.byteCount += byteCount
            return state.events.count == 1
        }
        if shouldWake, !wake() {
            close()
        }
    }
}
