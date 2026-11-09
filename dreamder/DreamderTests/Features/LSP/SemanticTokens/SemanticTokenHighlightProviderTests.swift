import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

@MainActor
private final class QueryOutcomeBox {
    var result: Result<[HighlightRange], any Error>?
}

@MainActor
private final class EditOutcomeBox {
    var result: Result<IndexSet, any Error>?
}

@MainActor
private struct TokenFixture {
    typealias Provider = SemanticTokenHighlightProvider<SemanticTokenStorage, SyncTestDocument>

    static let documentText = "hello world and more"

    let harness: SyncTestServer
    let provider: Provider
    let textView: TextView

    static func capabilities() -> ServerCapabilities {
        var capabilities = ScriptedServerConnection.incrementalCapabilities()
        capabilities.semanticTokensProvider = .optionA(
            .init(legend: .init(tokenTypes: ["keyword"], tokenModifiers: ["declaration"]))
        )
        return capabilities
    }

    static func make(fullTokens: String?) async throws -> TokenFixture {
        let harness = try await SyncTestServer.make(capabilities: capabilities())
        if let fullTokens {
            try harness.connection.script(
                .textDocumentSemanticTokensFull,
                SyncTestServer.decode(SemanticTokens.self, fullTokens)
            )
        }
        return try await attach(to: harness)
    }

    static func attach(to harness: SyncTestServer) async throws -> TokenFixture {
        let document = try await harness.open(text: documentText)
        let provider = document.languageServerObjects.highlightProvider
        let textView = TextView(string: documentText)
        provider.setUp(textView: textView, codeLanguage: .swift)
        await provider.latestRefresh?.value
        return TokenFixture(harness: harness, provider: provider, textView: textView)
    }

    func scriptDelta(_ json: String) throws {
        try harness.connection.script(
            .textDocumentSemanticTokensFullDelta,
            SyncTestServer.decode(SemanticTokensDelta.self, json)
        )
    }

    func scriptFullTokensForDeltaRequest(_ json: String) throws {
        try harness.connection.script(
            .textDocumentSemanticTokensFullDelta,
            SyncTestServer.decode(SemanticTokens.self, json)
        )
    }

    func parkEdit() async throws -> Task<IndexSet, Never> {
        let task = Task { await provider.invalidatedIndicesAfterEdit() }
        try await eventually { provider.hasPendingEdit }
        return task
    }

    func highlights(in range: NSRange) async throws -> [HighlightRange] {
        try await provider.highlights(in: range, textView: textView)
    }
}

@MainActor
@Suite(.uiGate)
struct SemanticTokenHighlightProviderTests {
    private typealias Provider = TokenFixture.Provider

    @Test
    func storedTokensAreDecodedWithCaptureAndModifiers() async throws {
        let fixture = try await TokenFixture.make(fullTokens: #"{"resultId":"r1","data":[0,0,5,0,1,0,6,5,0,0]}"#)

        let highlights = try await fixture.highlights(in: NSRange(location: 0, length: 20))

        #expect(highlights.map(\.range) == [NSRange(location: 0, length: 5), NSRange(location: 6, length: 5)])
        #expect(highlights.map(\.capture) == [.keyword, .keyword])
        #expect(highlights.map(\.modifiers) == [[.declaration], []])
    }

    @Test
    func emptyDeltaResponsesKeepTheParkedEditAndTheStoredTokens() async throws {
        let fixture = try await TokenFixture.make(fullTokens: #"{"resultId":"r1","data":[0,0,5,0,1]}"#)
        let parked = try await fixture.parkEdit()

        try await fixture.provider.documentDidChange()

        #expect(fixture.harness.connection.requestCount(.textDocumentSemanticTokensFullDelta) == 1)
        #expect(fixture.provider.hasPendingEdit)
        let highlights = try await fixture.highlights(in: NSRange(location: 0, length: 20))
        #expect(highlights.map(\.range) == [NSRange(location: 0, length: 5)])

        try fixture.scriptDelta(#"{"resultId":"r2","edits":[]}"#)
        try await fixture.provider.documentDidChange()
        #expect(await parked.value == IndexSet())
    }

    @Test
    func tokensCrossingTheQueryEndAreClamped() async throws {
        let fixture = try await TokenFixture.make(fullTokens: #"{"resultId":"r1","data":[0,0,5,0,1,0,6,5,0,0]}"#)

        let highlights = try await fixture.highlights(in: NSRange(location: 0, length: 8))

        #expect(highlights.map(\.range) == [NSRange(location: 0, length: 5), NSRange(location: 6, length: 2)])
    }

    @Test
    func tokensWithoutCaptureModifiersOrExtentAreDropped() async throws {
        let fixture = try await TokenFixture.make(
            fullTokens: #"{"resultId":"r1","data":[0,0,5,0,1,0,6,2,99,0,0,2,0,0,0,0,2,3,99,1]}"#
        )

        let highlights = try await fixture.highlights(in: NSRange(location: 0, length: 20))

        #expect(highlights.map(\.range) == [NSRange(location: 0, length: 5), NSRange(location: 10, length: 3)])
        #expect(highlights.map(\.capture) == [.keyword, nil])
        #expect(highlights.map(\.modifiers) == [[.declaration], [.declaration]])
    }

    @Test
    func rangesOutsideTheDocumentFailTheQuery() async throws {
        let fixture = try await TokenFixture.make(fullTokens: #"{"resultId":"r1","data":[0,0,5,0,1]}"#)

        await #expect(throws: Provider.HighlightError.lspRangeFailure) {
            _ = try await fixture.highlights(in: NSRange(location: 500, length: 3))
        }
    }

    @Test
    func protocolQueriesDeliverHighlightsAndFailures() async throws {
        let fixture = try await TokenFixture.make(fullTokens: #"{"resultId":"r1","data":[0,0,5,0,1]}"#)
        let success = QueryOutcomeBox()
        let failure = QueryOutcomeBox()

        fixture.provider.queryHighlightsFor(
            textView: fixture.textView,
            range: NSRange(location: 0, length: 20)
        ) { success.result = $0 }
        fixture.provider.queryHighlightsFor(
            textView: fixture.textView,
            range: NSRange(location: 500, length: 3)
        ) { failure.result = $0 }
        try await eventually { success.result != nil && failure.result != nil }

        guard case let .success(highlights)? = success.result else {
            Issue.record("expected highlights")
            return
        }
        #expect(highlights.map(\.range) == [NSRange(location: 0, length: 5)])
        guard case let .failure(error)? = failure.result else {
            Issue.record("expected failure")
            return
        }
        #expect(error as? Provider.HighlightError == .lspRangeFailure)
    }

    @Test
    func deltaResponsesInvalidateTheChangedRangesAndReplaceTokens() async throws {
        let fixture = try await TokenFixture.make(fullTokens: #"{"resultId":"r1","data":[0,0,5,0,1]}"#)
        try fixture.scriptDelta(#"{"resultId":"r2","edits":[{"start":0,"deleteCount":5,"data":[0,0,3,0,1]}]}"#)
        let invalidated = try await fixture.parkEdit()

        try await fixture.provider.documentDidChange()

        #expect(await invalidated.value == IndexSet(integersIn: 0..<5))
        #expect(fixture.harness.connection.requestCount(.textDocumentSemanticTokensFullDelta) == 1)
        let highlights = try await fixture.highlights(in: NSRange(location: 0, length: 20))
        #expect(highlights.map(\.range) == [NSRange(location: 0, length: 3)])
    }

    @Test
    func fullResponsesToDeltaRequestsInvalidateTheWholeDocument() async throws {
        let fixture = try await TokenFixture.make(fullTokens: #"{"resultId":"r1","data":[0,0,5,0,1]}"#)
        try fixture.scriptFullTokensForDeltaRequest(#"{"resultId":"r2","data":[0,2,4,0,1]}"#)
        let invalidated = try await fixture.parkEdit()

        try await fixture.provider.documentDidChange()

        #expect(await invalidated.value == IndexSet(integersIn: fixture.textView.documentRange))
        let highlights = try await fixture.highlights(in: NSRange(location: 0, length: 20))
        #expect(highlights.map(\.range) == [NSRange(location: 2, length: 4)])
    }

    @Test
    func tokensWithoutResultIdAreRequestedInFullAgain() async throws {
        let fixture = try await TokenFixture.make(fullTokens: #"{"data":[0,0,5,0,1]}"#)
        #expect(fixture.harness.connection.requestCount(.textDocumentSemanticTokensFull) == 1)

        try await fixture.provider.documentDidChange()

        #expect(fixture.harness.connection.requestCount(.textDocumentSemanticTokensFull) == 2)
        #expect(fixture.harness.connection.requestCount(.textDocumentSemanticTokensFullDelta) == 0)
        withExtendedLifetime(fixture.textView) {}
    }

    @Test
    func aNewerEditCompletesThePreviousOneWithAnEmptySet() async throws {
        let fixture = try await TokenFixture.make(fullTokens: #"{"resultId":"r1","data":[0,0,5,0,1]}"#)
        try fixture.scriptDelta(#"{"resultId":"r2","edits":[{"start":0,"deleteCount":5,"data":[0,0,3,0,1]}]}"#)
        let first = EditOutcomeBox()
        let second = EditOutcomeBox()

        fixture.provider.applyEdit(
            textView: fixture.textView,
            range: NSRange(location: 0, length: 0),
            delta: 1
        ) { first.result = $0 }
        fixture.provider.applyEdit(
            textView: fixture.textView,
            range: NSRange(location: 1, length: 0),
            delta: 1
        ) { second.result = $0 }
        try await eventually { first.result != nil }
        #expect(second.result == nil)

        try await fixture.provider.documentDidChange()
        try await eventually { second.result != nil }

        guard case let .success(firstIndexes)? = first.result, case let .success(secondIndexes)? = second.result else {
            Issue.record("expected both edits to succeed")
            return
        }
        #expect(firstIndexes == IndexSet())
        #expect(secondIndexes == IndexSet(integersIn: 0..<5))
        withExtendedLifetime(fixture.textView) {}
    }

    @Test
    func parkedQueriesAreCancelledOnceTokensArePending() async throws {
        let harness = try await SyncTestServer.make(capabilities: TokenFixture.capabilities())
        let document = try await harness.open(text: TokenFixture.documentText)
        let provider = document.languageServerObjects.highlightProvider
        let textView = TextView(string: TokenFixture.documentText)
        let parked = Task { try await provider.highlights(in: NSRange(location: 0, length: 5), textView: textView) }
        try await eventually { provider.pendingHighlightCount == 1 }

        provider.setUp(textView: textView, codeLanguage: .swift)

        await #expect(throws: HighlightProvidingError.operationCancelled) { _ = try await parked.value }
        #expect(provider.pendingHighlightCount == 0)
    }

    @Test
    func failedTokenRequestsDoNotBreakTheRefreshAndSurfaceFromDocumentChanges() async throws {
        let capabilities = TokenFixture.capabilities()
        let scripted = ScriptedServerConnection(capabilities: capabilities)
        let failing = FaultInjectingConnection(inner: scripted, failingRequests: [.textDocumentSemanticTokensFull])
        let server = try await SyncTestServer.makeServer(connection: failing, capabilities: capabilities)
        let harness = SyncTestServer(connection: scripted, server: server)

        let fixture = try await TokenFixture.attach(to: harness)

        #expect(fixture.provider.latestRefresh != nil)
        await #expect(throws: FaultInjectionError.self) { try await fixture.provider.documentDidChange() }
        #expect(fixture.provider.pendingHighlightCount == 0)
        withExtendedLifetime(fixture.textView) {}
    }

    @Test
    func documentRangeIsEmptyWithoutATextView() {
        #expect(Provider().documentRange == .zero)
    }
}
