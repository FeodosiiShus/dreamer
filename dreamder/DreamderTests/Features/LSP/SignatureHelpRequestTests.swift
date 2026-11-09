import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct SignatureHelpRequestTests {
    private let uri = syncTestDocumentURI
    private let position = Position(line: 1, character: 4)

    private struct Harness {
        let connection: SignatureHelpServerConnection
        let harness: SyncTestServer

        var server: SyncTestServer.Server {
            harness.server
        }
    }

    private func make(provider: SignatureHelpOptions? = SignatureHelpOptions()) async throws -> Harness {
        let capabilities = SignatureHelpFixtures.capabilities(provider: provider)
        let connection = SignatureHelpServerConnection(capabilities: capabilities)
        let server = try await SyncTestServer.makeServer(connection: connection, capabilities: capabilities)
        return Harness(connection: connection, harness: SyncTestServer(connection: connection.inner, server: server))
    }

    @Test
    func requestCarriesTriggerKindTriggerCharacterRetriggerAndTheActiveSignatureHelp() async throws {
        let harness = try await make()
        let active = SignatureHelpFixtures.twoOverloads(activeSignature: 1, activeParameter: 1)
        let answer = SignatureHelpFixtures.twoOverloads(activeSignature: 1, activeParameter: 2)
        harness.connection.answer(with: answer)
        let context = SignatureHelpContext.typed(",", activeSignatureHelp: active)

        let response = try await harness.server.requestSignatureHelp(for: uri, position: position, context: context)

        #expect(response == answer)
        let params = try #require(harness.connection.receivedParams.first)
        #expect(harness.connection.receivedParams.count == 1)
        #expect(params.textDocument == TextDocumentIdentifier(uri: uri))
        #expect(params.position == position)
        #expect(params.context.triggerKind == .triggerCharacter)
        #expect(params.context.triggerCharacter == ",")
        #expect(params.context.isRetrigger)
        #expect(params.context.activeSignatureHelp == active)
    }

    @Test
    func invokedRequestWithoutAnActiveHelpIsNotARetrigger() async throws {
        let harness = try await make()

        let response = try await harness.server.requestSignatureHelp(
            for: uri,
            position: position,
            context: .invoked(activeSignatureHelp: nil)
        )

        #expect(response == nil)
        let params = try #require(harness.connection.receivedParams.first)
        #expect(params.context.triggerKind == .invoked)
        #expect(params.context.triggerCharacter == nil)
        #expect(!params.context.isRetrigger)
        #expect(params.context.activeSignatureHelp == nil)
    }

    @Test
    func answersDependOnTheContextSoRepeatedRequestsAreNeverCached() async throws {
        let harness = try await make()
        harness.connection.enqueue([SignatureHelpFixtures.oneOverload(activeParameter: 0), SignatureHelpFixtures.oneOverload(activeParameter: 1)])
        let context = SignatureHelpContext.contentChange(activeSignatureHelp: nil)

        let first = try await harness.server.requestSignatureHelp(for: uri, position: position, context: context)
        let second = try await harness.server.requestSignatureHelp(for: uri, position: position, context: context)

        #expect(harness.connection.receivedParams.count == 2)
        #expect(first?.activeParameter == 0)
        #expect(second?.activeParameter == 1)
    }

    @Test
    func requestFlushesPendingEditsBeforeAskingTheServer() async throws {
        let harness = try await make()
        let document = try await harness.harness.open(batchInterval: .seconds(60))
        document.languageServerObjects.textCoordinator.recordEdit(
            uri: uri,
            range: SyncTestServer.range(0, 0, 0),
            string: "e"
        )

        _ = try await harness.server.requestSignatureHelp(
            for: uri,
            position: position,
            context: .invoked(activeSignatureHelp: nil)
        )

        #expect(harness.connection.didChangesAtRequest == [1])
    }

    @Test
    func failedRequestsAreRethrown() async throws {
        let harness = try await make()
        harness.connection.failRequests(true)

        await #expect(throws: SignatureHelpTestError.self) {
            _ = try await harness.server.requestSignatureHelp(
                for: uri,
                position: position,
                context: .invoked(activeSignatureHelp: nil)
            )
        }
        #expect(harness.connection.receivedParams.count == 1)
    }

    @Test
    func staticProviderWithoutCharactersFallsBackToParenAndComma() async throws {
        let harness = try await make()

        let capability = try #require(harness.server.signatureHelpCapability)

        #expect(capability.triggerCharacters == ["(", ","])
        #expect(capability.retriggerCharacters.isEmpty)
    }

    @Test
    func staticProviderCharactersAreReadFromTheCapabilities() async throws {
        let harness = try await make(provider: SignatureHelpOptions(triggerCharacters: ["<"], retriggerCharacters: [";"]))

        let capability = try #require(harness.server.signatureHelpCapability)

        #expect(capability.triggerCharacters == ["<"])
        #expect(capability.retriggerCharacters == [";"])
    }

    @Test
    func serverWithoutAProviderOrRegistrationHasNoSignatureHelp() async throws {
        let harness = try await make(provider: nil)

        #expect(harness.server.signatureHelpCapability == nil)
    }

    @Test
    func dynamicRegistrationEnablesSignatureHelpAndOverridesTheCharacters() async throws {
        let harness = try await make(provider: nil)
        harness.server.dynamicCapabilities.register([
            Registration(
                id: "signature",
                method: "textDocument/signatureHelp",
                registerOptions: ["triggerCharacters": ["!"], "retriggerCharacters": ["?"]]
            )
        ])

        let capability = try #require(harness.server.signatureHelpCapability)

        #expect(capability.triggerCharacters == ["!"])
        #expect(capability.retriggerCharacters == ["?"])
    }

    @Test
    func dynamicRegistrationWithoutOptionsUsesTheFallbackCharacters() async throws {
        let harness = try await make(provider: nil)
        harness.server.dynamicCapabilities.register([Registration(id: "signature", method: "textDocument/signatureHelp")])

        let capability = try #require(harness.server.signatureHelpCapability)

        #expect(capability.triggerCharacters == ["(", ","])
    }
}
