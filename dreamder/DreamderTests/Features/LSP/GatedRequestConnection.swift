import Foundation
import LanguageClient
import LanguageServerProtocol
@testable import Dreamder

final class GatedRequestConnection: ServerConnection, Sendable {
    let inner: ScriptedServerConnection
    let gatedMethods: Set<ClientRequest.Method>
    let gate: LSPServiceGate

    init(inner: ScriptedServerConnection, gatedMethods: Set<ClientRequest.Method>, gate: LSPServiceGate) {
        self.inner = inner
        self.gatedMethods = gatedMethods
        self.gate = gate
    }

    var eventSequence: EventSequence {
        inner.eventSequence
    }

    func sendNotification(_ notif: ClientNotification) async throws {
        try await inner.sendNotification(notif)
    }

    func sendRequest<Response: Decodable & Sendable>(_ request: ClientRequest) async throws -> Response {
        if gatedMethods.contains(request.method) {
            await gate.wait()
        }
        return try await inner.sendRequest(request)
    }
}
