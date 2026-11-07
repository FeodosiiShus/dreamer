//
//  BufferingServerConnection.swift
//  DreamderTests
//
//  Created by Khan Winter on 9/10/24.
//

import Foundation
import LanguageClient
import LanguageServerProtocol
import Synchronization
import JSONRPC

/// Mock server connection that retains all requests and notifications in an array for comparing later.
///
/// To listen for changes, this type produces an async stream of all requests and notifications. Use the
/// `clientEventSequence` sequence to receive a copy of both whenever they're updated.
/// 
final class BufferingServerConnection: ServerConnection, Sendable {
    typealias ClientEventSequence = AsyncStream<([ClientRequest], [ClientNotification])>

    private struct State {
        var id = 0
        var clientRequests: [ClientRequest] = []
        var clientNotifications: [ClientNotification] = []
    }

    let eventSequence: EventSequence
    let clientEventSequence: ClientEventSequence
    private let clientEventContinuation: ClientEventSequence.Continuation
    private let state = Mutex(State())

    var clientRequests: [ClientRequest] { state.withLock { $0.clientRequests } }
    var clientNotifications: [ClientNotification] { state.withLock { $0.clientNotifications } }

    init() {
        let (sequence, _) = EventSequence.makeStream()
        self.eventSequence = sequence
        (clientEventSequence, clientEventContinuation) = ClientEventSequence.makeStream()
    }

    func sendNotification(_ notif: ClientNotification) async throws {
        let snapshot = state.withLock { state in
            state.clientNotifications.append(notif)
            return (state.clientRequests, state.clientNotifications)
        }
        clientEventContinuation.yield(snapshot)
    }

    func sendRequest<Response: Decodable & Sendable>(_ request: ClientRequest) async throws -> Response {
        let snapshot = state.withLock { state in
            state.clientRequests.append(request)
            state.id += 1
            return (state.clientRequests, state.clientNotifications)
        }
        defer {
            clientEventContinuation.yield(snapshot)
        }
        let response: Codable
        switch request {
        case .initialize:
            var capabilities = ServerCapabilities()
            capabilities.textDocumentSync = .optionA(.init(
                openClose: true, change: .incremental, willSave: true, willSaveWaitUntil: false, save: .optionA(true)
            ))
            response = InitializationResponse(capabilities: .init(), serverInfo: nil)
        default:
            response = JSONRPCResponse(id: .numericId(0), result: JSONRPCErrors.internalError)
        }
        let data = try JSONEncoder().encode(response)
        return try JSONDecoder().decode(Response.self, from: data)
    }
}
