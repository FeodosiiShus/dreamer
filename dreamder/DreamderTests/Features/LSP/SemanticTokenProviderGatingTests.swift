import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

@MainActor
private final class HighlightResultBox {
    var result: Result<[HighlightRange], any Error>?
}

@MainActor
@Suite(.uiGate)
struct SemanticTokenProviderGatingTests {
    typealias Provider = SemanticTokenHighlightProvider<SemanticTokenStorage, SyncTestDocument>

    private let uri = syncTestDocumentURI
    private let fullTokensJSON = #"{"resultId":"r1","data":[]}"#

    private func semanticRequests(_ harness: SyncTestServer) -> Int {
        harness.connection.log.filter { $0.hasPrefix("textDocument/semanticTokens") }.count
    }

    private func query(_ provider: Provider, _ textView: TextView, _ box: HighlightResultBox) {
        provider.queryHighlightsFor(textView: textView, range: NSRange(location: 0, length: 5)) { result in
            box.result = result
        }
    }

    private func isEmptySuccess(_ result: Result<[HighlightRange], any Error>?) -> Bool {
        guard case let .success(ranges)? = result else { return false }
        return ranges.isEmpty
    }

    private func isCancellation(_ result: Result<[HighlightRange], any Error>?) -> Bool {
        guard case let .failure(error)? = result, let providing = error as? HighlightProvidingError else {
            return false
        }
        if case .operationCancelled = providing {
            return true
        }
        return false
    }

    @Test
    func supportsSemanticTokensFollowsTheServerCapability() async throws {
        let unsupported = try await SyncTestServer.makeIncremental()
        let supported = try await SyncTestServer.makeIncremental(semanticTokens: true)

        #expect(unsupported.server.supportsSemanticTokens == false)
        #expect(supported.server.supportsSemanticTokens)

        supported.server.serverCapabilities.semanticTokensProvider = nil
        #expect(supported.server.supportsSemanticTokens == false)
    }

    @Test
    func queriesCompleteImmediatelyWithAnEmptyResultWhenTheServerHasNoProvider() async throws {
        let harness = try await SyncTestServer.makeIncremental()
        let document = try await harness.open()
        let textView = TextView(string: "hello world")
        let box = HighlightResultBox()

        query(document.languageServerObjects.highlightProvider, textView, box)

        try await eventually { isEmptySuccess(box.result) }
    }

    @Test
    func queriesCompleteImmediatelyWithAnEmptyResultWithoutAServer() async throws {
        let provider = Provider()
        let textView = TextView(string: "hello world")
        let box = HighlightResultBox()

        query(provider, textView, box)

        try await eventually { isEmptySuccess(box.result) }
    }

    @Test
    func documentChangesNeverRequestTokensFromAServerWithoutAProvider() async throws {
        let harness = try await SyncTestServer.makeIncremental()
        let document = try await harness.open()
        let provider = document.languageServerObjects.highlightProvider
        let textView = TextView(string: "hello world")
        provider.setUp(textView: textView, codeLanguage: .swift)

        try await provider.documentDidChange()
        try await harness.server.documentChanged(uri: uri, changes: [])
        try await harness.server.reloadDocument(document)
        try await Task.sleep(for: .milliseconds(50))

        #expect(semanticRequests(harness) == 0)
        #expect(harness.didChanges.count == 2)
        withExtendedLifetime(textView) {}
    }

    @Test
    func parkedHighlightCallbacksAreCompletedWithAnEmptyResultWhenTheProviderDisappears() async throws {
        let harness = try await SyncTestServer.makeIncremental(semanticTokens: true)
        let document = try await harness.open()
        let provider = document.languageServerObjects.highlightProvider
        let textView = TextView(string: "hello world")
        let box = HighlightResultBox()
        provider.setUp(textView: textView, codeLanguage: .swift)
        await provider.latestRefresh?.value
        query(provider, textView, box)
        try await eventually { provider.pendingHighlightCount == 1 }
        #expect(box.result == nil)
        let requestsWhileParked = semanticRequests(harness)

        harness.server.serverCapabilities.semanticTokensProvider = nil
        try await provider.documentDidChange()

        try await eventually { isEmptySuccess(box.result) }
        #expect(semanticRequests(harness) == requestsWhileParked)
        withExtendedLifetime(textView) {}
    }

    @Test
    func aServerWithAProviderIsAskedForTokensAndParkedCallbacksAreCancelled() async throws {
        var capabilities = ScriptedServerConnection.incrementalCapabilities()
        capabilities.semanticTokensProvider = .optionA(.init(legend: .init(tokenTypes: [], tokenModifiers: [])))
        let scripted = ScriptedServerConnection(capabilities: capabilities)
        let gate = LSPServiceGate()
        let gated = GatedRequestConnection(inner: scripted, gatedMethods: [.textDocumentSemanticTokensFull], gate: gate)
        let server = try await SyncTestServer.makeServer(connection: gated, capabilities: capabilities)
        let harness = SyncTestServer(connection: scripted, server: server)
        try harness.connection.script(
            .textDocumentSemanticTokensFull,
            SyncTestServer.decode(SemanticTokens.self, fullTokensJSON)
        )
        let document = try await harness.open()
        let provider = document.languageServerObjects.highlightProvider
        let textView = TextView(string: "hello world")
        let box = HighlightResultBox()
        provider.setUp(textView: textView, codeLanguage: .swift)
        query(provider, textView, box)
        try await eventually { provider.pendingHighlightCount == 1 }
        #expect(box.result == nil)

        gate.open()
        try await eventually { isCancellation(box.result) }

        #expect(semanticRequests(harness) >= 1)
        #expect(harness.connection.requestCount(.textDocumentSemanticTokensFull) >= 1)
        withExtendedLifetime(textView) {}
    }

    @Test
    func bindingAProviderToAServerRefreshesTokensOnceTheTextViewIsAttached() async throws {
        let harness = try await SyncTestServer.makeIncremental(semanticTokens: true)
        let document = try await harness.open()
        let provider = Provider()
        let textView = TextView(string: "hello world")
        provider.setUp(textView: textView, codeLanguage: .swift)
        try await Task.sleep(for: .milliseconds(50))
        #expect(semanticRequests(harness) == 0)

        provider.setUp(server: harness.server, document: document)
        try await eventually { semanticRequests(harness) >= 1 }

        withExtendedLifetime(textView) {}
    }

    @Test
    func requestsFlushPendingEditsOnlyWhenAskedTo() async throws {
        let harness = try await SyncTestServer.makeIncremental(semanticTokens: true)
        let document = try await harness.open(batchInterval: .seconds(60))
        let coordinator = document.languageServerObjects.textCoordinator
        func edit() {
            coordinator.recordEdit(uri: uri, range: SyncTestServer.range(0, 0, 0), string: "e")
        }

        edit()
        _ = try await harness.server.requestSemanticTokens(for: uri, flushingPendingEdits: false)
        _ = try await harness.server.requestSemanticTokens(
            for: uri,
            previousResultId: "r1",
            flushingPendingEdits: false
        )
        #expect(harness.didChanges.isEmpty)
        #expect(coordinator.hasPendingChanges)

        _ = try await harness.server.requestSemanticTokens(for: uri)
        #expect(harness.connection.log.suffix(2) == ["textDocument/didChange", "textDocument/semanticTokens/full"])

        edit()
        _ = try await harness.server.requestSemanticTokens(for: uri, previousResultId: "r1")
        #expect(
            harness.connection.log.suffix(2) == ["textDocument/didChange", "textDocument/semanticTokens/full/delta"]
        )
        #expect(harness.didChanges.count == 2)
    }

    @Test
    func failedTokenRequestsThrow() async throws {
        let capabilities = SyncTestServer.capabilities(
            sync: ScriptedServerConnection.incrementalCapabilities().textDocumentSync,
            semanticTokens: true
        )
        let scripted = ScriptedServerConnection(capabilities: capabilities)
        let failing = FaultInjectingConnection(
            inner: scripted,
            failingRequests: [.textDocumentSemanticTokensFull, .textDocumentSemanticTokensFullDelta]
        )
        let server = try await SyncTestServer.makeServer(connection: failing, capabilities: capabilities)

        await #expect(throws: (any Error).self) { _ = try await server.requestSemanticTokens(for: uri) }
        await #expect(throws: (any Error).self) {
            _ = try await server.requestSemanticTokens(for: uri, previousResultId: "r1")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func editFlushDocumentChangedDocumentDidChangeCompletesWithoutDeadlock() async throws {
        let harness = try await SyncTestServer.makeIncremental(semanticTokens: true)
        try harness.connection.script(
            .textDocumentSemanticTokensFull,
            SyncTestServer.decode(SemanticTokens.self, fullTokensJSON)
        )
        let document = try await harness.open(batchInterval: .seconds(60))
        let coordinator = document.languageServerObjects.textCoordinator
        let provider = document.languageServerObjects.highlightProvider
        let textView = TextView(string: "hello world")
        provider.setUp(textView: textView, codeLanguage: .swift)
        try await eventually { semanticRequests(harness) >= 1 }
        let before = semanticRequests(harness)

        coordinator.recordEdit(uri: uri, range: SyncTestServer.range(0, 0, 0), string: "e")
        await coordinator.flushPendingChanges()

        #expect(harness.didChanges.count == 1)
        #expect(semanticRequests(harness) > before)
        withExtendedLifetime(textView) {}
    }
}
