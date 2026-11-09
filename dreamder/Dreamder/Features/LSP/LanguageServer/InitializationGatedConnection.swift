import Foundation
import LanguageClient
import LanguageServerProtocol
import Synchronization

nonisolated final class InitializationGatedConnection: ServerConnection, Sendable {
    private struct State {
        var isOpen = false
        var isClosed = false
        var pending: [ServerEvent] = []
        var forwardTask: Task<Void, Never>?
    }

    let eventSequence: EventSequence

    private let inner: any ServerConnection & Sendable
    private let continuation: EventSequence.Continuation
    private let state = Mutex(State())

    init(_ inner: any ServerConnection & Sendable) {
        self.inner = inner
        (eventSequence, continuation) = EventSequence.makeStream()
        let events = inner.eventSequence
        let task = Task { [weak self] in
            for await event in events {
                self?.receive(event)
            }
            self?.continuation.finish()
        }
        state.withLock { $0.forwardTask = task }
    }

    deinit {
        state.withLock { $0.forwardTask }?.cancel()
        continuation.finish()
    }

    func open() {
        state.withLock { state in
            guard !state.isOpen else { return }
            state.isOpen = true
            for event in state.pending {
                continuation.yield(event)
            }
            state.pending.removeAll()
        }
    }

    func sendNotification(_ notif: ClientNotification) async throws {
        try await inner.sendNotification(notif)
    }

    func sendRequest<Response: Decodable & Sendable>(_ request: ClientRequest) async throws -> Response {
        try await inner.sendRequest(request)
    }

    func close() {
        state.withLock { state in
            state.isClosed = true
            state.pending.removeAll()
        }
    }

    private func receive(_ event: ServerEvent) {
        state.withLock { state in
            if case .request = event {
                if state.isClosed { return }
                if !state.isOpen {
                    state.pending.append(event)
                    return
                }
            }
            continuation.yield(event)
        }
    }
}
