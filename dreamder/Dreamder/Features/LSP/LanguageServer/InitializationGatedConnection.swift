import Foundation
import LanguageClient
import LanguageServerProtocol

final class InitializationGatedConnection: ServerConnection, @unchecked Sendable {
    let eventSequence: EventSequence

    private let inner: any ServerConnection
    private let continuation: EventSequence.Continuation
    private let lock = NSLock()
    private var isOpen = false
    private var pending: [ServerEvent] = []
    private var forwardTask: Task<Void, Never>?

    init(_ inner: any ServerConnection) {
        self.inner = inner
        (eventSequence, continuation) = EventSequence.makeStream()
        let events = inner.eventSequence
        forwardTask = Task { [weak self] in
            for await event in events {
                self?.receive(event)
            }
            self?.continuation.finish()
        }
    }

    deinit {
        forwardTask?.cancel()
        continuation.finish()
    }

    func open() {
        lock.lock()
        defer { lock.unlock() }
        guard !isOpen else { return }
        isOpen = true
        for event in pending {
            continuation.yield(event)
        }
        pending.removeAll()
    }

    func sendNotification(_ notif: ClientNotification) async throws {
        try await inner.sendNotification(notif)
    }

    func sendRequest<Response: Decodable & Sendable>(_ request: ClientRequest) async throws -> Response {
        try await inner.sendRequest(request)
    }

    private func receive(_ event: ServerEvent) {
        lock.lock()
        defer { lock.unlock() }
        if !isOpen, case .request = event {
            pending.append(event)
            return
        }
        continuation.yield(event)
    }
}
