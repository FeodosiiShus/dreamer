import Foundation
import Synchronization

nonisolated final class StructureReaderProbe: Sendable {
    private struct State {
        var urls: [URL] = []
        var onMainThread: [Bool] = []
        var isReleased = false
        var waiter: CheckedContinuation<Void, Never>?
    }

    private let state = Mutex(State())
    private let text: String

    init(text: String) {
        self.text = text
    }

    var urls: [URL] {
        state.withLock { $0.urls }
    }

    var readsOnMainThread: [Bool] {
        state.withLock { $0.onMainThread }
    }

    func release() {
        let waiter = state.withLock { state -> CheckedContinuation<Void, Never>? in
            state.isReleased = true
            defer { state.waiter = nil }
            return state.waiter
        }
        waiter?.resume()
    }

    @concurrent
    func read(_ url: URL) async -> String? {
        record(url)
        await withCheckedContinuation { continuation in
            let isAlreadyReleased = state.withLock { state -> Bool in
                if state.isReleased { return true }
                state.waiter = continuation
                return false
            }
            if isAlreadyReleased {
                continuation.resume()
            }
        }
        return text
    }

    private func record(_ url: URL) {
        let onMain = pthread_main_np() != 0
        state.withLock {
            $0.urls.append(url)
            $0.onMainThread.append(onMain)
        }
    }
}
