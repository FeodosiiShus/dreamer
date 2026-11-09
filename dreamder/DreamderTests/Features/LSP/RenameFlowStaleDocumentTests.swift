import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

@MainActor
private final class StaleRenamePresenter: RenamePresenting {
    var messages: [String] = []
    var answer: String? = "greetings"

    func showMessage(_ message: String) {
        messages.append(message)
    }

    func requestName(for target: RenameTarget) async -> String? {
        answer
    }
}

@MainActor
private final class StaleRenameApplier {
    var edits: [WorkspaceEdit] = []

    func apply(_ edit: WorkspaceEdit) async -> ApplyWorkspaceEditResult {
        edits.append(edit)
        return ApplyWorkspaceEditResult(applied: true)
    }
}

@MainActor
@Suite(.serialized, .uiGate)
struct RenameFlowStaleDocumentTests {
    private let uri = syncTestDocumentURI
    private let openText = "hello world"

    private func makeServer() async throws -> SyncTestServer {
        var capabilities = ScriptedServerConnection.incrementalCapabilities()
        capabilities.renameProvider = .optionB(RenameOptions(prepareProvider: false))
        let harness = try await SyncTestServer.make(capabilities: capabilities)
        _ = try await harness.open(text: openText)
        let edit = try SyncTestServer.decode(
            WorkspaceEdit.self,
            #"""
            {"changes":{"\#(uri)":[{"range":{"start":{"line":0,"character":0},\#
            "end":{"line":0,"character":5}},"newText":"greetings"}]}}
            """#
        )
        try harness.connection.script(.textDocumentRename, edit)
        return harness
    }

    private func run(
        _ harness: SyncTestServer,
        currentText: String?,
        presenter: StaleRenamePresenter,
        applier: StaleRenameApplier
    ) async {
        let request = RenameRequest(
            documentURI: uri,
            position: Position(line: 0, character: 2),
            documentText: openText,
            symbol: "hello"
        )
        let backend = RenameBackend.make(
            client: harness.server,
            documentText: { currentText },
            apply: { edit in await applier.apply(edit) }
        )
        await RenameFlow.run(request: request, backend: backend, presenter: presenter)
    }

    @Test
    func aRenameIsNotAppliedWhenTheDocumentChangedWhileTheServerComputedIt() async throws {
        let harness = try await makeServer()
        let presenter = StaleRenamePresenter()
        let applier = StaleRenameApplier()

        await run(harness, currentText: "hello brave world", presenter: presenter, applier: applier)

        #expect(harness.connection.requestCount(.textDocumentRename) == 1)
        #expect(applier.edits.isEmpty)
        #expect(presenter.messages == ["Cannot rename: The document changed while the rename was computed"])
    }

    @Test
    func aRenameIsNotAppliedWhenTheDocumentTextIsNoLongerAvailable() async throws {
        let harness = try await makeServer()
        let presenter = StaleRenamePresenter()
        let applier = StaleRenameApplier()

        await run(harness, currentText: nil, presenter: presenter, applier: applier)

        #expect(applier.edits.isEmpty)
        #expect(presenter.messages == [RenameMessages.failure(reason: RenameMessages.documentChanged)])
    }

    @Test
    func aRenameIsAppliedWhenTheDocumentIsStillTheSnapshotItWasRequestedFor() async throws {
        let harness = try await makeServer()
        let presenter = StaleRenamePresenter()
        let applier = StaleRenameApplier()

        await run(harness, currentText: openText, presenter: presenter, applier: applier)

        #expect(applier.edits.count == 1)
        #expect(presenter.messages.isEmpty)
    }
}
