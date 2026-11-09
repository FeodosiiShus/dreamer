import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

extension RenameFlowTests {
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
