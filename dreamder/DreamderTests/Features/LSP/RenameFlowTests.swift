import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

@MainActor
private final class RenameFlowPresenter: RenamePresenting {
    var messages: [String] = []
    var prompted: [RenameTarget] = []
    var answer: String?

    func showMessage(_ message: String) {
        messages.append(message)
    }

    func requestName(for target: RenameTarget) async -> String? {
        prompted.append(target)
        return answer
    }
}

@MainActor
private final class RenameFlowApplier {
    var edits: [WorkspaceEdit] = []
    var result = ApplyWorkspaceEditResult(applied: true)

    func apply(_ edit: WorkspaceEdit) async -> ApplyWorkspaceEditResult {
        edits.append(edit)
        return result
    }
}

@MainActor
@Suite(.uiGate)
struct RenameFlowTests {
    private let uri = syncTestDocumentURI
    private let caret = Position(line: 0, character: 2)

    private func renameCapabilities(prepare: Bool) -> ServerCapabilities {
        var capabilities = ScriptedServerConnection.incrementalCapabilities()
        capabilities.renameProvider = .optionB(RenameOptions(prepareProvider: prepare))
        return capabilities
    }

    private func makeHarness(prepare: Bool = true, text: String = "hello world") async throws -> SyncTestServer {
        let harness = try await SyncTestServer.make(capabilities: renameCapabilities(prepare: prepare))
        _ = try await harness.open(text: text)
        return harness
    }

    private func request(symbol: String = "hello", text: String = "hello world") -> RenameRequest {
        RenameRequest(documentURI: uri, position: caret, documentText: text, symbol: symbol)
    }

    private func backend(
        _ server: SyncTestServer.Server,
        applier: RenameFlowApplier
    ) -> RenameBackend {
        RenameBackend.make(client: server) { edit in await applier.apply(edit) }
    }

    private func renameParams(_ connection: ScriptedServerConnection) -> [RenameParams] {
        connection.requests.compactMap { request in
            if case let .rename(params, _) = request {
                return params
            }
            return nil
        }
    }

    private func prepareParams(_ connection: ScriptedServerConnection) -> [PrepareRenameParams] {
        connection.requests.compactMap { request in
            if case let .prepareRename(params, _) = request {
                return params
            }
            return nil
        }
    }

    private func edit(_ json: String) throws -> WorkspaceEdit {
        try SyncTestServer.decode(WorkspaceEdit.self, json)
    }

    private func singleFileEdit(newText: String) throws -> WorkspaceEdit {
        try edit(
            #"{"changes":{"\#(uri)":[{"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":5}},"newText":"\#(newText)"}]}}"#
        )
    }

    private func run(
        _ harness: SyncTestServer,
        presenter: RenameFlowPresenter,
        applier: RenameFlowApplier,
        request: RenameRequest? = nil
    ) async {
        await RenameFlow.run(
            request: request ?? self.request(),
            backend: backend(harness.server, applier: applier),
            presenter: presenter
        )
    }

    @Test
    func lspRenameTestRenameAppliesWorkspaceEditFromServer() async throws {
        let harness = try await makeHarness()
        let applier = RenameFlowApplier()
        let presenter = RenameFlowPresenter()
        presenter.answer = "greetings"
        let expected = try singleFileEdit(newText: "greetings")
        try harness.connection.script(
            .textDocumentPrepareRename,
            RangeWithPlaceholder(range: SyncTestServer.range(0, 0, 5), placeholder: "hello")
        )
        try harness.connection.script(.textDocumentRename, expected)

        await run(harness, presenter: presenter, applier: applier)

        #expect(prepareParams(harness.connection) == [
            TextDocumentPositionParams(textDocument: TextDocumentIdentifier(uri: uri), position: caret)
        ])
        #expect(presenter.prompted == [RenameTarget(name: "hello", range: SyncTestServer.range(0, 0, 5))])
        #expect(renameParams(harness.connection) == [
            RenameParams(textDocument: TextDocumentIdentifier(uri: uri), position: caret, newName: "greetings")
        ])
        #expect(applier.edits == [expected])
        #expect(presenter.messages.isEmpty)
    }

    @Test
    func lspRenameTestRenameAppliesEditsOnMultipleLines() async throws {
        let text = "foo bar\nfoo baz\nfoo qux"
        let harness = try await makeHarness(text: text)
        let applier = RenameFlowApplier()
        let presenter = RenameFlowPresenter()
        presenter.answer = "renamed"
        let expected = try edit(
            #"""
            {"changes":{"\#(uri)":[
            {"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":3}},"newText":"renamed"},
            {"range":{"start":{"line":1,"character":0},"end":{"line":1,"character":3}},"newText":"renamed"},
            {"range":{"start":{"line":2,"character":0},"end":{"line":2,"character":3}},"newText":"renamed"}]}}
            """#
        )
        try harness.connection.script(
            .textDocumentPrepareRename,
            RangeWithPlaceholder(range: SyncTestServer.range(0, 0, 3), placeholder: "foo")
        )
        try harness.connection.script(.textDocumentRename, expected)

        await run(harness, presenter: presenter, applier: applier, request: request(symbol: "foo", text: text))

        #expect(applier.edits == [expected])
        #expect(applier.edits.first?.changes?[uri]?.count == 3)
    }

    @Test
    func lspRenameTestRenameXmlTagEditsBothTagsInOneFile() async throws {
        let text = "<tag>text</tag>"
        let harness = try await makeHarness(text: text)
        let applier = RenameFlowApplier()
        let presenter = RenameFlowPresenter()
        presenter.answer = "newtag"
        let expected = try edit(
            #"""
            {"changes":{"\#(uri)":[
            {"range":{"start":{"line":0,"character":1},"end":{"line":0,"character":4}},"newText":"newtag"},
            {"range":{"start":{"line":0,"character":11},"end":{"line":0,"character":14}},"newText":"newtag"}]}}
            """#
        )
        try harness.connection.script(
            .textDocumentPrepareRename,
            RangeWithPlaceholder(range: SyncTestServer.range(0, 1, 4), placeholder: "tag")
        )
        try harness.connection.script(.textDocumentRename, expected)

        await run(harness, presenter: presenter, applier: applier, request: request(symbol: "tag", text: text))

        #expect(renameParams(harness.connection).map(\.newName) == ["newtag"])
        #expect(applier.edits == [expected])
    }

    @Test
    func aWorkspaceEditWithChangesInSeveralFilesReachesTheApplierUntouched() async throws {
        let harness = try await makeHarness(prepare: false)
        let applier = RenameFlowApplier()
        let presenter = RenameFlowPresenter()
        presenter.answer = "greetings"
        let other = "file:///tmp/sync/other.swift"
        let expected = try edit(
            #"""
            {"changes":{
            "\#(uri)":[{"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":5}},"newText":"greetings"}],
            "\#(other)":[{"range":{"start":{"line":4,"character":2},"end":{"line":4,"character":7}},"newText":"greetings"}]}}
            """#
        )
        try harness.connection.script(.textDocumentRename, expected)

        await run(harness, presenter: presenter, applier: applier)

        #expect(applier.edits == [expected])
        #expect(Set(applier.edits.first?.changes?.keys.map { $0 } ?? []) == [uri, other])
    }

    @Test
    func lspRenameTestRenameAppliesRenameFileOperationTogetherWithTextEdits() async throws {
        let harness = try await makeHarness(text: "class Foo")
        let applier = RenameFlowApplier()
        let presenter = RenameFlowPresenter()
        presenter.answer = "Bar"
        let oldURI = "file:///tmp/sync/Foo.txt"
        let newURI = "file:///tmp/sync/Bar.txt"
        let expected = try edit(
            #"""
            {"documentChanges":[
            {"textDocument":{"uri":"\#(oldURI)","version":null},"edits":[{"range":{"start":{"line":0,"character":6},"end":{"line":0,"character":9}},"newText":"Bar"}]},
            {"kind":"rename","oldUri":"\#(oldURI)","newUri":"\#(newURI)","options":{}}]}
            """#
        )
        try harness.connection.script(
            .textDocumentPrepareRename,
            RangeWithPlaceholder(range: SyncTestServer.range(0, 6, 9), placeholder: "Foo")
        )
        try harness.connection.script(.textDocumentRename, expected)

        await run(harness, presenter: presenter, applier: applier, request: request(symbol: "Foo", text: "class Foo"))

        #expect(applier.edits == [expected])
        let changes = try #require(applier.edits.first?.documentChanges)
        #expect(changes.count == 2)
        guard case .renameFile(let rename) = changes[1] else {
            Issue.record("expected a rename file operation")
            return
        }
        #expect(rename.oldUri == oldURI)
        #expect(rename.newUri == newURI)
    }

    @Test
    func lspRenameTestRenameAppliesDeleteFileOperationTogetherWithTextEdits() async throws {
        let harness = try await makeHarness(prepare: false, text: "class Baz")
        let applier = RenameFlowApplier()
        let presenter = RenameFlowPresenter()
        presenter.answer = "Qux"
        let obsolete = "file:///tmp/sync/Obsolete.txt"
        let expected = try edit(
            #"""
            {"documentChanges":[
            {"textDocument":{"uri":"\#(uri)","version":null},"edits":[{"range":{"start":{"line":0,"character":6},"end":{"line":0,"character":9}},"newText":"Qux"}]},
            {"kind":"delete","uri":"\#(obsolete)","options":{}}]}
            """#
        )
        try harness.connection.script(.textDocumentRename, expected)

        await run(harness, presenter: presenter, applier: applier, request: request(symbol: "Baz", text: "class Baz"))

        #expect(applier.edits == [expected])
    }

    @Test
    func lspRenameTestAbortingRenameDoesNotSendServerRequest() async throws {
        let harness = try await makeHarness()
        let applier = RenameFlowApplier()
        let presenter = RenameFlowPresenter()
        presenter.answer = nil
        try harness.connection.script(
            .textDocumentPrepareRename,
            RangeWithPlaceholder(range: SyncTestServer.range(0, 0, 5), placeholder: "hello")
        )

        await run(harness, presenter: presenter, applier: applier)

        #expect(presenter.prompted.count == 1)
        #expect(harness.connection.requestCount(.textDocumentRename) == 0)
        #expect(applier.edits.isEmpty)
        #expect(presenter.messages.isEmpty)
    }

    @Test
    func lspRenameTestPrepareRenameWithRangeOnlyUsesDocumentText() async throws {
        let harness = try await makeHarness()
        let applier = RenameFlowApplier()
        let presenter = RenameFlowPresenter()
        try harness.connection.script(.textDocumentPrepareRename, SyncTestServer.range(0, 6, 11))

        await run(harness, presenter: presenter, applier: applier, request: request(symbol: "hello"))

        #expect(presenter.prompted == [RenameTarget(name: "world", range: SyncTestServer.range(0, 6, 11))])
    }

    @Test
    func lspRenameTestPrepareRenameWithDefaultBehaviorFallsBackToWordRange() async throws {
        let harness = try await makeHarness()
        let applier = RenameFlowApplier()
        let presenter = RenameFlowPresenter()
        try harness.connection.script(
            .textDocumentPrepareRename,
            PrepareRenameDefaultBehavior(defaultBehavior: true)
        )

        await run(harness, presenter: presenter, applier: applier)

        #expect(presenter.prompted == [RenameTarget(name: "hello", range: nil)])
    }

    @Test
    func aDisabledDefaultBehaviorShowsTheNotRenameableMessage() async throws {
        let harness = try await makeHarness()
        let applier = RenameFlowApplier()
        let presenter = RenameFlowPresenter()
        try harness.connection.script(
            .textDocumentPrepareRename,
            PrepareRenameDefaultBehavior(defaultBehavior: false)
        )

        await run(harness, presenter: presenter, applier: applier)

        #expect(presenter.prompted.isEmpty)
        #expect(presenter.messages == ["Cannot rename this element"])
    }

    @Test
    func aNullPrepareRenameResponseShowsTheNotRenameableMessage() async throws {
        let harness = try await makeHarness()
        let applier = RenameFlowApplier()
        let presenter = RenameFlowPresenter()

        await run(harness, presenter: presenter, applier: applier)

        #expect(harness.connection.requestCount(.textDocumentPrepareRename) == 1)
        #expect(presenter.prompted.isEmpty)
        #expect(presenter.messages == ["Cannot rename this element"])
        #expect(harness.connection.requestCount(.textDocumentRename) == 0)
    }

    @Test
    func lspRenameTestPrepareProviderDisabledFallsBackToWordRange() async throws {
        let harness = try await makeHarness(prepare: false)
        let applier = RenameFlowApplier()
        let presenter = RenameFlowPresenter()
        presenter.answer = "greetings"

        await run(harness, presenter: presenter, applier: applier)

        #expect(harness.connection.requestCount(.textDocumentPrepareRename) == 0)
        #expect(presenter.prompted == [RenameTarget(name: "hello", range: nil)])
        #expect(renameParams(harness.connection).map(\.newName) == ["greetings"])
    }

    @Test
    func withoutAWordUnderTheCaretAndNoPrepareSupportTheElementIsNotRenameable() async throws {
        let harness = try await makeHarness(prepare: false)
        let applier = RenameFlowApplier()
        let presenter = RenameFlowPresenter()

        await run(harness, presenter: presenter, applier: applier, request: request(symbol: ""))

        #expect(presenter.prompted.isEmpty)
        #expect(presenter.messages == ["Cannot rename this element"])
    }

    @Test
    func aDynamicallyRegisteredPrepareProviderIsUsed() async throws {
        let harness = try await makeHarness(prepare: false)
        harness.server.dynamicCapabilities.register([
            Registration(id: "rename", method: "textDocument/rename", registerOptions: ["prepareProvider": true])
        ])
        let applier = RenameFlowApplier()
        let presenter = RenameFlowPresenter()
        try harness.connection.script(
            .textDocumentPrepareRename,
            RangeWithPlaceholder(range: SyncTestServer.range(0, 0, 5), placeholder: "hello")
        )

        await run(harness, presenter: presenter, applier: applier)

        #expect(harness.connection.requestCount(.textDocumentPrepareRename) == 1)
        #expect(presenter.prompted.count == 1)
    }

    @Test
    func prepareSupportComesFromStaticOrDynamicCapabilities() async throws {
        let harness = try await makeHarness(prepare: false)
        let server = harness.server

        server.serverCapabilities.renameProvider = nil
        #expect(!server.supportsPrepareRename)
        server.serverCapabilities.renameProvider = .optionA(true)
        #expect(!server.supportsPrepareRename)
        server.serverCapabilities.renameProvider = .optionB(RenameOptions(prepareProvider: nil))
        #expect(!server.supportsPrepareRename)
        server.serverCapabilities.renameProvider = .optionB(RenameOptions(prepareProvider: true))
        #expect(server.supportsPrepareRename)

        server.serverCapabilities.renameProvider = nil
        server.dynamicCapabilities.register([
            Registration(id: "off", method: "textDocument/rename", registerOptions: ["prepareProvider": false])
        ])
        #expect(!server.supportsPrepareRename)
        server.dynamicCapabilities.register([
            Registration(id: "on", method: "textDocument/rename", registerOptions: ["prepareProvider": true])
        ])
        #expect(server.supportsPrepareRename)
    }

    @Test
    func aNullRenameResponseShowsNothingToRename() async throws {
        let harness = try await makeHarness(prepare: false)
        let applier = RenameFlowApplier()
        let presenter = RenameFlowPresenter()
        presenter.answer = "greetings"

        await run(harness, presenter: presenter, applier: applier)

        #expect(harness.connection.requestCount(.textDocumentRename) == 1)
        #expect(applier.edits.isEmpty)
        #expect(presenter.messages == ["Nothing to rename"])
    }

    @Test
    func anEditThatIsNotAppliedShowsTheReason() async throws {
        let harness = try await makeHarness(prepare: false)
        let applier = RenameFlowApplier()
        applier.result = ApplyWorkspaceEditResult(applied: false, failureReason: "file is read-only", failedChange: 1)
        let presenter = RenameFlowPresenter()
        presenter.answer = "greetings"
        try harness.connection.script(.textDocumentRename, try singleFileEdit(newText: "greetings"))

        await run(harness, presenter: presenter, applier: applier)

        #expect(applier.edits.count == 1)
        #expect(presenter.messages == ["Cannot rename: file is read-only"])
    }

    @Test
    func anEditThatIsNotAppliedWithoutAReasonShowsTheGenericText() async throws {
        let harness = try await makeHarness(prepare: false)
        let applier = RenameFlowApplier()
        applier.result = ApplyWorkspaceEditResult(applied: false)
        let presenter = RenameFlowPresenter()
        presenter.answer = "greetings"
        try harness.connection.script(.textDocumentRename, try singleFileEdit(newText: "greetings"))

        await run(harness, presenter: presenter, applier: applier)

        #expect(presenter.messages == ["Cannot rename: The edit could not be applied"])
    }

    @Test
    func aFailingPrepareRequestShowsTheErrorAndStops() async throws {
        let caps = renameCapabilities(prepare: true)
        let scripted = ScriptedServerConnection(capabilities: caps)
        let failing = FaultInjectingConnection(inner: scripted, failingRequests: [.textDocumentPrepareRename])
        let server = try await SyncTestServer.makeServer(connection: failing, capabilities: caps)
        let applier = RenameFlowApplier()
        let presenter = RenameFlowPresenter()
        presenter.answer = "greetings"

        await RenameFlow.run(
            request: request(),
            backend: backend(server, applier: applier),
            presenter: presenter
        )

        #expect(presenter.prompted.isEmpty)
        #expect(presenter.messages.count == 1)
        #expect(presenter.messages.first?.hasPrefix("Cannot rename: ") == true)
        #expect(scripted.requestCount(.textDocumentRename) == 0)
    }

    @Test
    func aFailingRenameRequestShowsTheError() async throws {
        let caps = renameCapabilities(prepare: false)
        let scripted = ScriptedServerConnection(capabilities: caps)
        let failing = FaultInjectingConnection(inner: scripted, failingRequests: [.textDocumentRename])
        let server = try await SyncTestServer.makeServer(connection: failing, capabilities: caps)
        let applier = RenameFlowApplier()
        let presenter = RenameFlowPresenter()
        presenter.answer = "greetings"

        await RenameFlow.run(
            request: request(),
            backend: backend(server, applier: applier),
            presenter: presenter
        )

        #expect(presenter.messages.count == 1)
        #expect(presenter.messages.first?.hasPrefix("Cannot rename: ") == true)
        #expect(applier.edits.isEmpty)
    }

    @Test
    func pendingEditsAreFlushedBeforeThePrepareAndRenameRequests() async throws {
        let harness = try await SyncTestServer.make(capabilities: renameCapabilities(prepare: true))
        let document = try await harness.open(batchInterval: .seconds(60))
        let applier = RenameFlowApplier()
        let presenter = RenameFlowPresenter()
        presenter.answer = "greetings"
        document.languageServerObjects.textCoordinator.recordEdit(
            uri: uri,
            range: SyncTestServer.range(0, 0, 0),
            string: "e"
        )
        try harness.connection.script(
            .textDocumentPrepareRename,
            RangeWithPlaceholder(range: SyncTestServer.range(0, 0, 5), placeholder: "hello")
        )

        await run(harness, presenter: presenter, applier: applier)

        let log = harness.connection.log
        #expect(log.suffix(3) == ["textDocument/didChange", "textDocument/prepareRename", "textDocument/rename"])
    }
}
