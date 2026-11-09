import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import JSONRPC
import LanguageClient
import LanguageServerProtocol
import Testing
@testable import Dreamder

final class SelectionRangeGateConnection: ServerConnection, Sendable {
    let inner: ScriptedServerConnection
    let started: AsyncStream<Void>
    private let startedContinuation: AsyncStream<Void>.Continuation
    private let releases: AsyncStream<Void>
    private let releaseContinuation: AsyncStream<Void>.Continuation

    init(inner: ScriptedServerConnection) {
        self.inner = inner
        (started, startedContinuation) = AsyncStream<Void>.makeStream()
        (releases, releaseContinuation) = AsyncStream<Void>.makeStream()
    }

    var eventSequence: EventSequence {
        inner.eventSequence
    }

    func release() {
        releaseContinuation.yield()
    }

    func sendNotification(_ notif: ClientNotification) async throws {
        try await inner.sendNotification(notif)
    }

    func sendRequest<Response: Decodable & Sendable>(_ request: ClientRequest) async throws -> Response {
        if request.method == .textDocumentSelectionRange {
            startedContinuation.yield()
            var iterator = releases.makeAsyncIterator()
            _ = await iterator.next()
        }
        return try await inner.sendRequest(request)
    }
}

@MainActor
private struct SelectionRangeHarness {
    let fixture: HostedSourceEditorFixture
    let hosted: HostedSourceEditor
    let coordinator: SelectionRangeCoordinator
    let controller: TextViewController
    let textView: TextView

    var selections: [NSRange] {
        textView.selectionManager.textSelections.map(\.range)
    }

    var reportedSelections: [NSRange] {
        controller.cursorPositions.map(\.range)
    }

    func select(_ ranges: [NSRange]) {
        textView.selectionManager.setSelectedRanges(ranges)
    }

    func close() {
        hosted.close()
    }
}

@MainActor
@Suite(.uiGate)
struct SelectionRangeCoordinatorTests {
    private static let source = "let alpha = 1\nlet beta = 2\nlet gamma = 3"

    private func range(_ location: Int, _ length: Int) -> NSRange {
        NSRange(location: location, length: length)
    }

    private func lsp(_ line: Int, _ start: Int, _ end: Int) -> LSPRange {
        LSPRange(start: Position(line: line, character: start), end: Position(line: line, character: end))
    }

    private func alphaChain() -> SelectionRange {
        let document = SelectionRange(
            range: LSPRange(start: Position(line: 0, character: 0), end: Position(line: 2, character: 13)),
            parent: nil
        )
        let line = SelectionRange(range: lsp(0, 0, 13), parent: document)
        return SelectionRange(range: lsp(0, 4, 9), parent: line)
    }

    private func betaChain() -> SelectionRange {
        let line = SelectionRange(range: lsp(1, 0, 12), parent: nil)
        return SelectionRange(range: lsp(1, 4, 8), parent: line)
    }

    private func makeServer(
        in directory: URL,
        connection: any ServerConnection & Sendable,
        supportsSelectionRange: Bool = true
    ) async throws -> LSPService.LanguageServerType {
        var capabilities = ScriptedServerConnection.incrementalCapabilities()
        if supportsSelectionRange {
            capabilities.selectionRangeProvider = .optionA(true)
        }
        let server = LSPService.LanguageServerType(
            languageId: .swift,
            binary: .init(execPath: "", args: [], env: nil),
            lspInstance: InitializingServer(
                server: connection,
                initializeParamsProvider: LSPService.LanguageServerType.getInitParams(workspacePath: directory.path())
            ),
            lspPid: -1,
            serverCapabilities: capabilities,
            rootPath: directory,
            logContainer: LanguageServerLogContainer(languageID: "swift")
        )
        _ = try await server.lspInstance.initializeIfNeeded()
        return server
    }

    private func makeHarness(
        in directory: URL,
        server: LSPService.LanguageServerType? = nil,
        usesDefaultProvider: Bool = false
    ) async throws -> SelectionRangeHarness {
        let fixture = try HostedSourceEditorFixture.make(in: directory, contents: Self.source)
        let coordinator: SelectionRangeCoordinator
        if usesDefaultProvider {
            coordinator = SelectionRangeCoordinator(editorInstance: fixture.editorInstance, codeFile: fixture.document)
        } else {
            coordinator = SelectionRangeCoordinator(
                editorInstance: fixture.editorInstance,
                codeFile: fixture.document,
                clientProvider: { server }
            )
        }
        let hosted = fixture.host(
            coordinators: [fixture.document.contentCoordinator, coordinator],
            size: NSSize(width: 900, height: 600)
        )
        try await eventually { hosted.controller?.textView != nil }
        let controller = try #require(hosted.controller)
        let textView = try #require(controller.textView)
        try await eventually { textView.textStorage.length == Self.source.utf16.count }
        return SelectionRangeHarness(
            fixture: fixture,
            hosted: hosted,
            coordinator: coordinator,
            controller: controller,
            textView: textView
        )
    }

    private func expandAll(_ harness: SelectionRangeHarness) async -> [[NSRange]] {
        var steps: [[NSRange]] = []
        for _ in 0..<5 {
            await harness.coordinator.expandSelection()
            steps.append(harness.selections)
        }
        return steps
    }

    @Test
    func theCoordinatorRegistersItselfInTheEditorHub() throws {
        let editor = EditorInstance(workspace: nil, file: CEWorkspaceFile(url: URL(filePath: "/fake/dir/file.swift")))
        let coordinator = SelectionRangeCoordinator(editorInstance: editor, codeFile: CodeFileDocument())

        #expect(EditorFeatureHubs.hub(for: editor).selectionRange === coordinator)
    }

    @Test
    func theDefaultClientProviderIsNilWithoutAFileOrARegisteredServer() throws {
        try withTempDir { directory in
            let editor = EditorInstance(workspace: nil, file: CEWorkspaceFile(url: URL(filePath: "/fake/dir/file.swift")))
            let withoutFile = SelectionRangeCoordinator(editorInstance: editor, codeFile: CodeFileDocument())
            #expect(withoutFile.clientProvider() == nil)

            let fixture = try HostedSourceEditorFixture.make(in: directory, contents: Self.source)
            let unregistered = SelectionRangeCoordinator(editorInstance: fixture.editorInstance, codeFile: fixture.document)
            #expect(unregistered.clientProvider() == nil)
        }
    }

    @Test
    func coordinatorsWithoutAControllerIgnoreTheCommands() async {
        let editor = EditorInstance(workspace: nil, file: CEWorkspaceFile(url: URL(filePath: "/fake/dir/file.swift")))
        let coordinator = SelectionRangeCoordinator(editorInstance: editor, codeFile: CodeFileDocument())

        await coordinator.expandSelection()
        coordinator.shrinkSelection()
        coordinator.destroy()
    }

    @Test
    func expandAndShrinkFollowTheServerChain() async throws {
        try await withTempDir { directory in
            let scripted = ScriptedServerConnection()
            try scripted.script(.textDocumentSelectionRange, [alphaChain()])
            let server = try await makeServer(in: directory, connection: scripted)
            let harness = try await makeHarness(in: directory, server: server)
            defer { harness.close() }
            harness.select([range(6, 0)])

            await harness.coordinator.expandSelection()
            #expect(harness.selections == [range(4, 5)])
            await harness.coordinator.expandSelection()
            #expect(harness.selections == [range(0, 13)])
            await harness.coordinator.expandSelection()
            #expect(harness.selections == [range(0, 40)])
            await harness.coordinator.expandSelection()
            #expect(harness.selections == [range(0, 40)])

            harness.coordinator.shrinkSelection()
            #expect(harness.selections == [range(0, 13)])
            harness.coordinator.shrinkSelection()
            #expect(harness.selections == [range(4, 5)])
            harness.coordinator.shrinkSelection()
            #expect(harness.selections == [range(6, 0)])
            harness.coordinator.shrinkSelection()
            #expect(harness.selections == [range(6, 0)])

            #expect(scripted.requestCount(.textDocumentSelectionRange) == 1)
            #expect(scripted.selectionRangeRequestParams.first?.positions == [Position(line: 0, character: 6)])
            #expect(scripted.selectionRangeRequestParams.first?.textDocument.uri == harness.fixture.document.languageServerURI)
        }
    }

    @Test
    func everyCaretGetsItsOwnChainFromOneRequest() async throws {
        try await withTempDir { directory in
            let scripted = ScriptedServerConnection()
            try scripted.script(.textDocumentSelectionRange, [alphaChain(), betaChain()])
            let server = try await makeServer(in: directory, connection: scripted)
            let harness = try await makeHarness(in: directory, server: server)
            defer { harness.close() }
            harness.select([range(20, 0), range(6, 0)])

            await harness.coordinator.expandSelection()
            #expect(harness.selections == [range(4, 5), range(18, 4)])
            await harness.coordinator.expandSelection()
            #expect(harness.selections == [range(0, 13), range(14, 12)])
            harness.coordinator.shrinkSelection()
            #expect(harness.selections == [range(4, 5), range(18, 4)])
            harness.coordinator.shrinkSelection()
            #expect(harness.selections == [range(6, 0), range(20, 0)])

            #expect(scripted.requestCount(.textDocumentSelectionRange) == 1)
            #expect(
                scripted.selectionRangeRequestParams.first?.positions
                    == [Position(line: 0, character: 6), Position(line: 1, character: 6)]
            )
        }
    }

    @Test
    func caretsThatExpandToTheSameRangeMerge() async throws {
        try await withTempDir { directory in
            let harness = try await makeHarness(in: directory)
            defer { harness.close() }
            harness.select([range(5, 0), range(7, 0)])

            await harness.coordinator.expandSelection()
            #expect(harness.selections == [range(4, 5)])
            harness.coordinator.shrinkSelection()
            #expect(harness.selections == [range(5, 0)])
        }
    }

    @Test
    func withoutAServerTheLadderGoesWordLineDocument() async throws {
        try await withTempDir { directory in
            let harness = try await makeHarness(in: directory)
            defer { harness.close() }
            harness.select([range(6, 0)])

            let steps = await expandAll(harness)

            #expect(steps == [[range(4, 5)], [range(0, 13)], [range(0, 40)], [range(0, 40)], [range(0, 40)]])
            harness.coordinator.shrinkSelection()
            #expect(harness.selections == [range(0, 13)])
            harness.coordinator.shrinkSelection()
            #expect(harness.selections == [range(4, 5)])
            harness.coordinator.shrinkSelection()
            #expect(harness.selections == [range(6, 0)])
        }
    }

    @Test
    func aServerWithoutTheCapabilityIsNeverAsked() async throws {
        try await withTempDir { directory in
            let scripted = ScriptedServerConnection()
            try scripted.script(.textDocumentSelectionRange, [alphaChain()])
            let server = try await makeServer(in: directory, connection: scripted, supportsSelectionRange: false)
            let harness = try await makeHarness(in: directory, server: server)
            defer { harness.close() }
            harness.select([range(6, 0)])

            await harness.coordinator.expandSelection()

            #expect(harness.selections == [range(4, 5)])
            #expect(scripted.requestCount(.textDocumentSelectionRange) == 0)
        }
    }

    @Test
    func aNullAnswerFallsBackToTheLadderAndIsNotRepeated() async throws {
        try await withTempDir { directory in
            let scripted = ScriptedServerConnection()
            let server = try await makeServer(in: directory, connection: scripted)
            let harness = try await makeHarness(in: directory, server: server)
            defer { harness.close() }
            harness.select([range(6, 0)])

            await harness.coordinator.expandSelection()
            await harness.coordinator.expandSelection()

            #expect(harness.selections == [range(0, 13)])
            #expect(scripted.requestCount(.textDocumentSelectionRange) == 1)
        }
    }

    @Test
    func aFailingRequestFallsBackToTheLadder() async throws {
        try await withTempDir { directory in
            let scripted = ScriptedServerConnection()
            try scripted.script(.textDocumentSelectionRange, [alphaChain()])
            let failing = FaultInjectingConnection(inner: scripted, failingRequests: [.textDocumentSelectionRange])
            let server = try await makeServer(in: directory, connection: failing)
            let harness = try await makeHarness(in: directory, server: server)
            defer { harness.close() }
            harness.select([range(6, 0)])

            await harness.coordinator.expandSelection()

            #expect(harness.selections == [range(4, 5)])
            #expect(scripted.requestCount(.textDocumentSelectionRange) == 0)
        }
    }

    @Test
    func anAnswerWithTheWrongNumberOfChainsIsIgnored() async throws {
        try await withTempDir { directory in
            let scripted = ScriptedServerConnection()
            let wrong = SelectionRange(range: lsp(0, 0, 3), parent: nil)
            try scripted.script(.textDocumentSelectionRange, [wrong])
            let server = try await makeServer(in: directory, connection: scripted)
            let harness = try await makeHarness(in: directory, server: server)
            defer { harness.close() }
            harness.select([range(6, 0), range(20, 0)])

            await harness.coordinator.expandSelection()

            #expect(harness.selections == [range(4, 5), range(18, 4)])
            #expect(scripted.requestCount(.textDocumentSelectionRange) == 1)
        }
    }

    @Test
    func theLadderContinuesWhereTheServerChainEnds() async throws {
        try await withTempDir { directory in
            let scripted = ScriptedServerConnection()
            try scripted.script(.textDocumentSelectionRange, [SelectionRange(range: lsp(0, 4, 9), parent: nil)])
            let server = try await makeServer(in: directory, connection: scripted)
            let harness = try await makeHarness(in: directory, server: server)
            defer { harness.close() }
            harness.select([range(6, 0)])

            let steps = await expandAll(harness)

            #expect(steps == [[range(4, 5)], [range(0, 13)], [range(0, 40)], [range(0, 40)], [range(0, 40)]])
            #expect(scripted.requestCount(.textDocumentSelectionRange) == 1)
        }
    }

    @Test
    func chainRangesOutsideTheDocumentAreDropped() async throws {
        try await withTempDir { directory in
            let scripted = ScriptedServerConnection()
            let outside = SelectionRange(range: lsp(9, 0, 3), parent: nil)
            try scripted.script(.textDocumentSelectionRange, [SelectionRange(range: lsp(0, 4, 9), parent: outside)])
            let server = try await makeServer(in: directory, connection: scripted)
            let harness = try await makeHarness(in: directory, server: server)
            defer { harness.close() }
            harness.select([range(6, 0)])

            await harness.coordinator.expandSelection()
            await harness.coordinator.expandSelection()

            #expect(harness.selections == [range(0, 13)])
        }
    }

    @Test
    func changingTheSelectionElsewhereDropsTheStack() async throws {
        try await withTempDir { directory in
            let harness = try await makeHarness(in: directory)
            defer { harness.close() }
            harness.select([range(6, 0)])
            await harness.coordinator.expandSelection()
            #expect(harness.selections == [range(4, 5)])

            harness.select([range(20, 0)])
            harness.coordinator.shrinkSelection()
            #expect(harness.selections == [range(20, 0)])

            await harness.coordinator.expandSelection()
            #expect(harness.selections == [range(18, 4)])
        }
    }

    @Test
    func returningToTheSameSelectionAfterAnExternalChangeDoesNotRevivePreviousSteps() async throws {
        try await withTempDir { directory in
            let harness = try await makeHarness(in: directory)
            defer { harness.close() }
            harness.select([range(6, 0)])
            await harness.coordinator.expandSelection()
            #expect(harness.selections == [range(4, 5)])

            harness.select([range(30, 0)])
            try await eventually { harness.reportedSelections == [range(30, 0)] }
            harness.select([range(4, 5)])
            try await eventually { harness.reportedSelections == [range(4, 5)] }
            harness.coordinator.shrinkSelection()

            #expect(harness.selections == [range(9, 0)])
        }
    }

    @Test
    func ourOwnSelectionChangesKeepTheStack() async throws {
        try await withTempDir { directory in
            let harness = try await makeHarness(in: directory)
            defer { harness.close() }
            harness.select([range(6, 0)])
            await harness.coordinator.expandSelection()
            try await eventually { harness.reportedSelections == [range(4, 5)] }
            await harness.coordinator.expandSelection()
            try await eventually { harness.reportedSelections == [range(0, 13)] }

            harness.coordinator.shrinkSelection()
            harness.coordinator.shrinkSelection()

            #expect(harness.selections == [range(6, 0)])
        }
    }

    @Test
    func aTextChangeDropsTheStack() async throws {
        try await withTempDir { directory in
            let harness = try await makeHarness(in: directory)
            defer { harness.close() }
            harness.select([range(6, 0)])
            await harness.coordinator.expandSelection()
            #expect(harness.selections == [range(4, 5)])

            harness.coordinator.textViewDidChangeText(controller: harness.controller)
            harness.coordinator.shrinkSelection()

            #expect(harness.selections == [range(9, 0)])
        }
    }

    @Test
    func aRealEditThroughTheTextViewAlsoDropsTheStack() async throws {
        try await withTempDir { directory in
            let harness = try await makeHarness(in: directory)
            defer { harness.close() }
            harness.select([range(6, 0)])
            await harness.coordinator.expandSelection()

            harness.textView.replaceCharacters(in: range(Self.source.utf16.count, 0), with: "\nlet delta = 4")
            harness.select([range(4, 5)])
            try await eventually { harness.reportedSelections == [range(4, 5)] }
            harness.coordinator.shrinkSelection()

            #expect(harness.selections == [range(9, 0)])
        }
    }

    @Test
    func shrinkingAUserSelectionWithoutHistoryWalksTheLadderDown() async throws {
        try await withTempDir { directory in
            let harness = try await makeHarness(in: directory)
            defer { harness.close() }
            harness.select([range(0, 13)])

            harness.coordinator.shrinkSelection()
            #expect(harness.selections == [range(12, 1)])
            harness.coordinator.shrinkSelection()
            #expect(harness.selections == [range(13, 0)])
            harness.coordinator.shrinkSelection()
            #expect(harness.selections == [range(13, 0)])
        }
    }

    @Test
    func noSelectionsMeansNothingToExpandOrShrink() async throws {
        try await withTempDir { directory in
            let harness = try await makeHarness(in: directory)
            defer { harness.close() }
            harness.select([])

            await harness.coordinator.expandSelection()
            harness.coordinator.shrinkSelection()

            #expect(harness.selections.isEmpty)
        }
    }

    @Test
    func aSecondExpandWaitsForTheFirstAndBuildsOnIt() async throws {
        try await withTempDir { directory in
            let scripted = ScriptedServerConnection()
            try scripted.script(.textDocumentSelectionRange, [alphaChain()])
            let gate = SelectionRangeGateConnection(inner: scripted)
            let server = try await makeServer(in: directory, connection: gate)
            let harness = try await makeHarness(in: directory, server: server)
            defer { harness.close() }
            harness.select([range(6, 0)])

            let first = Task { await harness.coordinator.expandSelection() }
            let second = Task { await harness.coordinator.expandSelection() }
            var started = gate.started.makeAsyncIterator()
            _ = await started.next()
            gate.release()
            await first.value
            await second.value

            #expect(harness.selections == [range(0, 13)])
            #expect(scripted.requestCount(.textDocumentSelectionRange) == 1)
        }
    }

    @Test
    func anExpansionWhoseSelectionMovedDuringTheRequestIsDiscarded() async throws {
        try await withTempDir { directory in
            let scripted = ScriptedServerConnection()
            try scripted.script(.textDocumentSelectionRange, [alphaChain()])
            let gate = SelectionRangeGateConnection(inner: scripted)
            let server = try await makeServer(in: directory, connection: gate)
            let harness = try await makeHarness(in: directory, server: server)
            defer { harness.close() }
            harness.select([range(6, 0)])

            let expansion = Task { await harness.coordinator.expandSelection() }
            var started = gate.started.makeAsyncIterator()
            _ = await started.next()
            harness.select([range(20, 0)])
            gate.release()
            await expansion.value

            #expect(harness.selections == [range(20, 0)])
        }
    }

    @Test
    func destroyedCoordinatorsStopReactingToCommands() async throws {
        try await withTempDir { directory in
            let harness = try await makeHarness(in: directory)
            defer { harness.close() }
            harness.select([range(6, 0)])
            await harness.coordinator.expandSelection()

            harness.coordinator.destroy()
            await harness.coordinator.expandSelection()
            harness.coordinator.shrinkSelection()

            #expect(harness.selections == [range(4, 5)])
        }
    }

    @Test
    func theDefaultProviderFindsTheServerOfTheDocumentInTheLSPService() async throws {
        try await withTempDir { directory in
            let service = LSPService.shared
            let scripted = ScriptedServerConnection()
            try scripted.script(.textDocumentSelectionRange, [alphaChain()])
            let server = try await makeServer(in: directory, connection: scripted)
            let harness = try await makeHarness(in: directory, usesDefaultProvider: true)
            defer { harness.close() }
            try await server.openDocument(harness.fixture.document)
            let key = LSPService.ClientKey(.swift, directory.path() + "/")
            service.languageClients[key] = server
            defer { service.languageClients[key] = nil }
            harness.select([range(6, 0)])

            await harness.coordinator.expandSelection()
            await harness.coordinator.expandSelection()

            #expect(harness.selections == [range(0, 13)])
            #expect(scripted.requestCount(.textDocumentSelectionRange) == 1)
        }
    }
}
