import Foundation
import JSONRPC
import LanguageClient
import LanguageServerProtocol
import Synchronization

enum InlayHintDecorationsServerError: Error {
    case unsupported
}

final class InlayHintDecorationsServerConnection: ServerConnection, Sendable {
    private struct State {
        var hints: [InlayHint]
        var failsInlayRequests: Bool
        var inlayRequestCount = 0
        var inlayRanges: [LSPRange] = []
        var configurationSettings: [LSPAny?] = []
        var inlayDelay: Duration = .zero
    }

    let eventSequence: EventSequence
    private let state: Mutex<State>

    init(hints: [InlayHint] = [], failsInlayRequests: Bool = false) {
        let (sequence, _) = EventSequence.makeStream()
        eventSequence = sequence
        state = Mutex(State(hints: hints, failsInlayRequests: failsInlayRequests))
    }

    var inlayRequestCount: Int {
        state.withLock { $0.inlayRequestCount }
    }

    var inlayRanges: [LSPRange] {
        state.withLock { $0.inlayRanges }
    }

    var configurationSettings: [LSPAny?] {
        state.withLock { $0.configurationSettings }
    }

    func setInlayDelay(_ delay: Duration) {
        state.withLock { $0.inlayDelay = delay }
    }

    func setHints(_ hints: [InlayHint]) {
        state.withLock { $0.hints = hints }
    }

    func sendNotification(_ notif: ClientNotification) async throws {
        if case .workspaceDidChangeConfiguration(let params) = notif {
            state.withLock { $0.configurationSettings.append(params.settings) }
        }
    }

    func sendRequest<Response: Decodable & Sendable>(_ request: ClientRequest) async throws -> Response {
        switch request {
        case .initialize:
            return try Self.decode(InitializationResponse(capabilities: ServerCapabilities(), serverInfo: nil))
        case .inlayHint(let params, _):
            let outcome = state.withLock { state in
                state.inlayRequestCount += 1
                state.inlayRanges.append(params.range)
                return (fails: state.failsInlayRequests, hints: state.hints, delay: state.inlayDelay)
            }
            if outcome.delay > .zero {
                try await Task.sleep(for: outcome.delay)
            }
            if outcome.fails {
                throw InlayHintDecorationsServerError.unsupported
            }
            return try Self.decode(outcome.hints)
        default:
            throw InlayHintDecorationsServerError.unsupported
        }
    }

    private static func decode<Response: Decodable, Payload: Encodable>(_ payload: Payload) throws -> Response {
        try JSONDecoder().decode(Response.self, from: JSONEncoder().encode(payload))
    }
}
