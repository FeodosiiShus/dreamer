import Foundation
import Synchronization
@testable import Dreamder

nonisolated final class StructureBuilderProbe: Sendable {
    private struct State {
        var texts: [String] = []
        var isReleased = false
        var waiters: [CheckedContinuation<Void, Never>] = []
    }

    private let state = Mutex(State())

    var texts: [String] {
        state.withLock { $0.texts }
    }

    func release() {
        let waiters = state.withLock { state -> [CheckedContinuation<Void, Never>] in
            state.isReleased = true
            defer { state.waiters = [] }
            return state.waiters
        }
        for waiter in waiters {
            waiter.resume()
        }
    }

    @concurrent
    func build(_ text: String) async -> [StructureNode] {
        state.withLock { $0.texts.append(text) }
        await withCheckedContinuation { continuation in
            let isAlreadyReleased = state.withLock { state -> Bool in
                if state.isReleased { return true }
                state.waiters.append(continuation)
                return false
            }
            if isAlreadyReleased {
                continuation.resume()
            }
        }
        let title = text.split(separator: "\n").first.map(String.init) ?? ""
        return [StructureNode(id: title, name: title, detail: nil, kind: .function, line: 1, column: 1, children: [])]
    }
}
