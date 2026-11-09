import Foundation
import JSONRPC
import LanguageClient
import LanguageServerProtocol
import Synchronization

enum ScriptedServerConnectionFailure: Error {
    case injected(String)
}

final class ScriptedServerConnection: ServerConnection, Sendable {
    private struct State {
        var requests: [ClientRequest] = []
        var notifications: [ClientNotification] = []
        var log: [String] = []
        var responses: [ClientRequest.Method: Data] = [:]
        var failingRequests: Set<ClientRequest.Method> = []
        var failingNotifications: Set<ClientNotification.Method> = []
    }

    let eventSequence: EventSequence
    private let eventContinuation: EventSequence.Continuation
    private let capabilities: ServerCapabilities
    private let state = Mutex(State())

    init(capabilities: ServerCapabilities = ScriptedServerConnection.incrementalCapabilities()) {
        self.capabilities = capabilities
        (eventSequence, eventContinuation) = EventSequence.makeStream()
    }

    static func incrementalCapabilities() -> ServerCapabilities {
        var capabilities = ServerCapabilities()
        capabilities.textDocumentSync = .optionA(TextDocumentSyncOptions(
            openClose: true, change: .incremental, willSave: false, willSaveWaitUntil: false, save: nil
        ))
        return capabilities
    }

    static func fullCapabilities() -> ServerCapabilities {
        var capabilities = ServerCapabilities()
        capabilities.textDocumentSync = .optionA(TextDocumentSyncOptions(
            openClose: true, change: .full, willSave: false, willSaveWaitUntil: false, save: nil
        ))
        return capabilities
    }

    var requests: [ClientRequest] { state.withLock { $0.requests } }
    var notifications: [ClientNotification] { state.withLock { $0.notifications } }
    var log: [String] { state.withLock { $0.log } }

    func requestCount(_ method: ClientRequest.Method) -> Int {
        state.withLock { $0.requests.filter { $0.method == method }.count }
    }

    func notificationCount(_ method: ClientNotification.Method) -> Int {
        state.withLock { $0.notifications.filter { $0.method == method }.count }
    }

    func script<Value: Encodable>(_ method: ClientRequest.Method, _ value: Value) throws {
        let data = try JSONEncoder().encode(value)
        state.withLock { $0.responses[method] = data }
    }

    func emit(_ event: ServerEvent) {
        eventContinuation.yield(event)
    }

    func failRequests(_ methods: Set<ClientRequest.Method>) {
        state.withLock { $0.failingRequests = methods }
    }

    func failNotifications(_ methods: Set<ClientNotification.Method>) {
        state.withLock { $0.failingNotifications = methods }
    }

    func finishEvents() {
        eventContinuation.finish()
    }

    func sendNotification(_ notif: ClientNotification) async throws {
        let shouldFail = state.withLock { state -> Bool in
            state.notifications.append(notif)
            state.log.append(notif.method.rawValue)
            return state.failingNotifications.contains(notif.method)
        }
        if shouldFail {
            throw ScriptedServerConnectionFailure.injected(notif.method.rawValue)
        }
    }

    func sendRequest<Response: Decodable & Sendable>(_ request: ClientRequest) async throws -> Response {
        let (data, shouldFail) = state.withLock { state -> (Data, Bool) in
            state.requests.append(request)
            state.log.append(request.method.rawValue)
            if state.failingRequests.contains(request.method) {
                return (Data(), true)
            }
            if case .initialize = request {
                let response = InitializationResponse(capabilities: capabilities, serverInfo: nil)
                let encoded = (try? JSONEncoder().encode(response)) ?? Data("null".utf8)
                return (encoded, false)
            }
            return (state.responses[request.method] ?? Data("null".utf8), false)
        }
        if shouldFail {
            throw ScriptedServerConnectionFailure.injected(request.method.rawValue)
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }
}
