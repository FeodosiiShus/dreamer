import Foundation
import JSONRPC
import LanguageServerProtocol
import Testing
@testable import Dreamder

@Suite
struct InitializationGatedConnectionTests {
    private final class Source: ServerConnection, Sendable {
        let eventSequence: EventSequence
        let continuation: EventSequence.Continuation

        init() {
            (eventSequence, continuation) = EventSequence.makeStream()
        }

        func sendNotification(_ notif: ClientNotification) async throws {}

        func sendRequest<Response: Decodable & Sendable>(_ request: ClientRequest) async throws -> Response {
            throw CancellationError()
        }
    }

    private func label(_ event: ServerEvent) -> String {
        switch event {
        case .notification(.windowLogMessage(let params)):
            return "log:\(params.message)"
        case .request(_, .workspaceConfiguration):
            return "request"
        default:
            return "other"
        }
    }

    @Test
    func requestsWaitForOpenWhileNotificationsPassThrough() async throws {
        let source = Source()
        let gate = InitializationGatedConnection(source)
        var iterator = gate.eventSequence.makeAsyncIterator()

        source.continuation.yield(.request(
            id: .numericId(1),
            request: .workspaceConfiguration(ConfigurationParams(items: []), { _ in })
        ))
        source.continuation.yield(.notification(.windowLogMessage(LogMessageParams(type: .info, message: "early"))))

        let first = try #require(await iterator.next())
        #expect(label(first) == "log:early")

        gate.open()
        let second = try #require(await iterator.next())
        #expect(label(second) == "request")

        source.continuation.yield(.request(
            id: .numericId(2),
            request: .workspaceConfiguration(ConfigurationParams(items: []), { _ in })
        ))
        let third = try #require(await iterator.next())
        #expect(label(third) == "request")
    }

    @Test
    func closedGateDropsLaterRequestsButStillPassesNotifications() async throws {
        let source = Source()
        let gate = InitializationGatedConnection(source)
        var iterator = gate.eventSequence.makeAsyncIterator()
        gate.open()
        gate.close()

        source.continuation.yield(.request(
            id: .numericId(1),
            request: .workspaceConfiguration(ConfigurationParams(items: []), { _ in })
        ))
        source.continuation.yield(.notification(.windowLogMessage(LogMessageParams(type: .info, message: "late"))))

        let next = try #require(await iterator.next())
        #expect(label(next) == "log:late")
    }

    @Test
    func closingBeforeOpenDiscardsQueuedRequests() async throws {
        let source = Source()
        let gate = InitializationGatedConnection(source)
        var iterator = gate.eventSequence.makeAsyncIterator()

        source.continuation.yield(.request(
            id: .numericId(1),
            request: .workspaceConfiguration(ConfigurationParams(items: []), { _ in })
        ))
        source.continuation.yield(.notification(.windowLogMessage(LogMessageParams(type: .info, message: "first"))))
        let first = try #require(await iterator.next())
        #expect(label(first) == "log:first")

        gate.close()
        gate.open()
        source.continuation.yield(.notification(.windowLogMessage(LogMessageParams(type: .info, message: "second"))))

        let second = try #require(await iterator.next())
        #expect(label(second) == "log:second")
    }
}
