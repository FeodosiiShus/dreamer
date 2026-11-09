import Foundation
import Synchronization

nonisolated final class FileEventBatcher: Sendable {
    typealias Handler = @Sendable ([DirectoryEventStream.Event]) async -> Void

    private struct State {
        var pending: [DirectoryEventStream.Event] = []
        var isDraining = false
        var isCancelled = false
    }

    private let window: Duration
    private let clock: any Clock<Duration>
    private let handler: Handler
    private let state = Mutex(State())

    init(
        window: Duration = .milliseconds(100),
        clock: any Clock<Duration> = ContinuousClock(),
        handler: @escaping Handler
    ) {
        self.window = window
        self.clock = clock
        self.handler = handler
    }

    func submit(_ events: [DirectoryEventStream.Event]) {
        guard !events.isEmpty else { return }
        let startsDraining = state.withLock { state -> Bool in
            guard !state.isCancelled else { return false }
            state.pending.append(contentsOf: events)
            guard !state.isDraining else { return false }
            state.isDraining = true
            return true
        }
        if startsDraining {
            Task { [self] in await drain() }
        }
    }

    func cancel() {
        state.withLock { state in
            state.isCancelled = true
            state.pending.removeAll()
        }
    }

    private func drain() async {
        while true {
            try? await clock.sleep(for: window)
            let batch = state.withLock { state -> [DirectoryEventStream.Event] in
                let batch = state.pending
                state.pending = []
                return batch
            }
            if !batch.isEmpty {
                await handler(batch)
            }
            let finished = state.withLock { state -> Bool in
                guard state.pending.isEmpty || state.isCancelled else { return false }
                state.isDraining = false
                return true
            }
            if finished { return }
        }
    }
}
