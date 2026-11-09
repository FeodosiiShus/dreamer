import AppKit
import CodeEditSourceEditor
import Foundation
import LanguageClient
import LanguageServerProtocol
import SwiftUI
import Testing
@testable import Dreamder

private func renameKeyEvent(_ keyCode: UInt16, flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
    try #require(NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: flags,
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: "",
        charactersIgnoringModifiers: "",
        isARepeat: false,
        keyCode: keyCode
    ))
}

@MainActor
private final class RenameNameResults {
    var values: [String?] = []

    func append(_ value: String?) {
        values.append(value)
    }

    func present(_ model: RenamePopupViewModel, in harness: RenameWindowHarness) async throws {
        Task { @MainActor in
            append(await RenamePanelHost.shared.present(model, anchor: nil, in: harness.controller))
        }
        try await eventually { harness.renameModel === model }
    }
}

@MainActor
private struct RenameWindowHarness {
    let workspace: WorkspaceDocument
    let controller: DreamderWindowController
    let window: NSWindow

    static func make(in directory: URL) throws -> RenameWindowHarness {
        let workspace = WorkspaceDocument()
        try workspace.read(from: directory, ofType: "")
        workspace.makeWindowControllers()
        let controller = try #require(workspace.windowControllers.first as? DreamderWindowController)
        let window = try #require(controller.window)
        window.isReleasedWhenClosed = false
        window.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: false)
        return RenameWindowHarness(workspace: workspace, controller: controller, window: window)
    }

    var panels: [ShowUsagesPanel] {
        window.childWindows?.compactMap { $0 as? ShowUsagesPanel } ?? []
    }

    var renamePanels: [ShowUsagesPanel] {
        panels.filter { $0.contentView is NSHostingView<RenamePopupView> }
    }

    var messagePanels: [ShowUsagesPanel] {
        panels.filter { $0.contentView is NSHostingView<ShowUsagesView> }
    }

    var renameModel: RenamePopupViewModel? {
        (renamePanels.first?.contentView as? NSHostingView<RenamePopupView>)?.rootView.model
    }

    func close() {
        for child in window.childWindows ?? [] {
            child.close()
        }
        window.close()
        workspace.close()
    }
}

@MainActor
@Suite(.uiGate)
struct RenamePopupViewModelTests {
    private func model(_ name: String = "hello") -> RenamePopupViewModel {
        RenamePopupViewModel(target: RenameTarget(name: name, range: nil))
    }

    @Test
    func theFieldIsPrefilledWithTheCurrentNameAndThePromptNamesIt() {
        let model = model("greeting")

        #expect(model.name == "greeting")
        #expect(model.prompt == "Rename greeting and its usages to:")
        #expect(model.panelWidth == 380)
        #expect(model.preferredHeight == 104)
    }

    @Test
    func validationStatesFollowTheTypedName() {
        let model = model()

        #expect(model.validation == .unchanged)
        #expect(!model.isConfirmEnabled)
        #expect(model.errorMessage == nil)

        model.name = "greetings"
        #expect(model.validation == .valid)
        #expect(model.isConfirmEnabled)
        #expect(model.errorMessage == nil)

        model.name = "two words"
        #expect(model.validation == .invalidIdentifier("two words"))
        #expect(!model.isConfirmEnabled)
        #expect(model.errorMessage == "'two words' is not a valid identifier")

        model.name = "   "
        #expect(model.validation == .empty)
        #expect(!model.isConfirmEnabled)
        #expect(model.errorMessage == "The name must not be empty")
    }

    @Test
    func confirmingSendsTheTrimmedNameOnlyWhenItIsValid() {
        let model = model()
        var confirmed: [String] = []
        model.onConfirm = { confirmed.append($0) }

        model.confirm()
        model.name = "bad name"
        model.confirm()
        model.name = "  greetings \n"
        model.confirm()

        #expect(confirmed == ["greetings"])
    }

    @Test
    func cancellingCallsTheCancelHandler() {
        let model = model()
        var cancelled = 0
        model.onCancel = { cancelled += 1 }

        model.cancel()

        #expect(cancelled == 1)
    }

    @Test
    func returnConfirmsAndEscapeCancels() throws {
        let model = model()
        var confirmed: [String] = []
        var cancelled = 0
        model.onConfirm = { confirmed.append($0) }
        model.onCancel = { cancelled += 1 }
        model.name = "greetings"

        #expect(model.handle(event: try renameKeyEvent(36)))
        #expect(model.handle(event: try renameKeyEvent(76)))
        #expect(confirmed == ["greetings", "greetings"])
        #expect(model.handle(event: try renameKeyEvent(53)))
        #expect(cancelled == 1)

        model.name = "bad name"
        #expect(model.handle(event: try renameKeyEvent(36)))
        #expect(confirmed.count == 2)
    }

    @Test
    func otherKeysAndModifiedKeysAreNotHandled() throws {
        let model = model()
        var confirmed = 0
        var cancelled = 0
        model.onConfirm = { _ in confirmed += 1 }
        model.onCancel = { cancelled += 1 }
        model.name = "greetings"

        #expect(model.handle(event: try renameKeyEvent(0)) == false)
        #expect(model.handle(event: try renameKeyEvent(36, flags: .command)) == false)
        #expect(model.handle(event: try renameKeyEvent(53, flags: .option)) == false)
        #expect(confirmed == 0)
        #expect(cancelled == 0)
    }
}

@MainActor
@Suite(.uiGate)
struct RenamePopupViewTests {
    private func model(_ name: String = "hello") -> RenamePopupViewModel {
        RenamePopupViewModel(target: RenameTarget(name: name, range: nil))
    }

    @Test
    func theFieldShowsTheCurrentNameAndTheViewRenders() async throws {
        let model = model("greeting")
        let hosted = HostedViewFixture.host(size: NSSize(width: 380, height: 104)) {
            RenamePopupView(model: model)
        }
        defer { hosted.close() }

        try await hosted.settle()

        #expect(hosted.views(of: NSTextField.self).contains { $0.stringValue == "greeting" })
        #expect(hosted.renders())
    }

    @Test
    func everyValidationStateRendersAndTheErrorLooksDifferent() async throws {
        let model = model()
        let hosted = HostedViewFixture.host(size: NSSize(width: 380, height: 104)) {
            RenamePopupView(model: model)
        }
        defer { hosted.close() }

        try await hosted.settle()
        let unchanged = hosted.snapshot()
        #expect(hosted.renders())

        model.name = "greetings"
        try await hosted.settle(.milliseconds(150))
        let valid = hosted.snapshot()
        #expect(hosted.renders())

        model.name = "two words"
        try await hosted.settle(.milliseconds(150))
        let invalid = hosted.snapshot()
        #expect(hosted.renders())

        model.name = ""
        try await hosted.settle(.milliseconds(150))
        let empty = hosted.snapshot()
        #expect(hosted.renders())

        #expect(HostedView.pixelsDiffer(valid, invalid))
        #expect(HostedView.pixelsDiffer(unchanged, valid))
        #expect(HostedView.pixelsDiffer(invalid, empty))
    }
}

@MainActor
@Suite(.serialized, .uiGate)
struct RenamePanelHostTests {
    private func model(_ name: String = "hello") -> RenamePopupViewModel {
        RenamePopupViewModel(target: RenameTarget(name: name, range: nil))
    }

    private func makeOrphanPresenter() -> RenamePanelPresenter {
        RenamePanelPresenter(controller: DreamderWindowController(window: nil, workspace: nil))
    }

    @Test
    func thePanelHostsTheFixedSizeRenameViewAsAChildWindow() async throws {
        try await withTempDir { directory in
            let harness = try RenameWindowHarness.make(in: directory)
            defer { harness.close() }
            let results = RenameNameResults()

            try await results.present(model(), in: harness)

            let panel = try #require(harness.renamePanels.first)
            let hosting = try #require(panel.contentView as? NSHostingView<RenamePopupView>)
            #expect(hosting.sizingOptions == [])
            #expect(panel.frame.size == NSSize(width: 380, height: 104))
            #expect(hosting.rootView.model.name == "hello")
            #expect(results.values.isEmpty)
        }
    }

    @Test
    func confirmingReportsTheTrimmedNameOnceAndClosesThePanel() async throws {
        try await withTempDir { directory in
            let harness = try RenameWindowHarness.make(in: directory)
            defer { harness.close() }
            let results = RenameNameResults()
            let model = model()

            try await results.present(model, in: harness)
            model.name = " greetings "
            model.confirm()

            try await eventually { results.values.count == 1 }
            #expect(results.values == ["greetings"])
            #expect(harness.renamePanels.isEmpty)
        }
    }

    @Test
    func cancellingAndClosingThePanelReportNil() async throws {
        try await withTempDir { directory in
            let harness = try RenameWindowHarness.make(in: directory)
            defer { harness.close() }
            let results = RenameNameResults()
            let first = model()

            try await results.present(first, in: harness)
            first.cancel()
            try await eventually { results.values.count == 1 }
            #expect(results.values == [nil])
            #expect(harness.renamePanels.isEmpty)

            try await results.present(model(), in: harness)
            harness.renamePanels.first?.close()

            try await eventually { results.values.count == 2 }
            #expect(results.values == [nil, nil])
        }
    }

    @Test
    func theKeyEventsOfThePanelConfirmAndCancel() async throws {
        try await withTempDir { directory in
            let harness = try RenameWindowHarness.make(in: directory)
            defer { harness.close() }
            let results = RenameNameResults()
            let confirming = model()

            try await results.present(confirming, in: harness)
            confirming.name = "greetings"
            let returnHandler = try #require(harness.renamePanels.first?.onKeyEvent)
            let handledReturn = returnHandler(try renameKeyEvent(36))
            #expect(handledReturn)
            try await eventually { results.values.count == 1 }
            #expect(results.values == ["greetings"])

            try await results.present(model(), in: harness)
            let escapeHandler = try #require(harness.renamePanels.first?.onKeyEvent)
            let handledEscape = escapeHandler(try renameKeyEvent(53))
            #expect(handledEscape)
            try await eventually { results.values.count == 2 }
            #expect(results.values == ["greetings", nil])
        }
    }

    @Test
    func anInvalidNameKeepsThePanelOpen() async throws {
        try await withTempDir { directory in
            let harness = try RenameWindowHarness.make(in: directory)
            defer { harness.close() }
            let results = RenameNameResults()
            let model = model()

            try await results.present(model, in: harness)
            model.name = "two words"
            model.confirm()

            #expect(results.values.isEmpty)
            #expect(harness.renamePanels.count == 1)
        }
    }

    @Test
    func presentingAgainReplacesTheOpenPanelAndCancelsItsRequest() async throws {
        try await withTempDir { directory in
            let harness = try RenameWindowHarness.make(in: directory)
            defer { harness.close() }
            let results = RenameNameResults()

            try await results.present(model("one"), in: harness)
            try await results.present(model("two"), in: harness)

            try await eventually { results.values.count == 1 }
            #expect(results.values == [nil])
            #expect(harness.renamePanels.count == 1)
            #expect(harness.renameModel?.name == "two")
        }
    }

    @Test
    func withoutAWindowTheRequestIsCancelledImmediately() async {
        let controller = DreamderWindowController(window: nil, workspace: nil)

        let name = await RenamePanelHost.shared.present(model(), anchor: nil, in: controller)

        #expect(name == nil)
    }

    @Test
    func requestNameSuspendsUntilTheUserConfirms() async throws {
        try await withTempDir { directory in
            let harness = try RenameWindowHarness.make(in: directory)
            defer { harness.close() }
            let target = RenameTarget(name: "hello", range: nil)

            let request = Task { await RenamePanelHost.shared.requestName(for: target, in: harness.controller) }
            try await eventually { harness.renameModel != nil }
            let model = try #require(harness.renameModel)
            model.name = "greetings"
            model.confirm()

            #expect(await request.value == "greetings")
        }
    }

    @Test
    func thePresenterShowsMessagesAndRequestsNamesThroughTheHosts() async throws {
        try await withTempDir { directory in
            let harness = try RenameWindowHarness.make(in: directory)
            defer { harness.close() }
            let presenter = RenamePanelPresenter(controller: harness.controller)

            presenter.showMessage("Nothing to rename")
            #expect(harness.messagePanels.count == 1)

            let request = Task { await presenter.requestName(for: RenameTarget(name: "hello", range: nil)) }
            try await eventually { harness.renameModel != nil }
            harness.renameModel?.cancel()

            #expect(await request.value == nil)
        }
    }

    @Test
    func aPresenterWhoseWindowControllerIsGoneDoesNothing() async {
        let presenter = makeOrphanPresenter()

        presenter.showMessage("ignored")
        let name = await presenter.requestName(for: RenameTarget(name: "hello", range: nil))

        #expect(name == nil)
    }
}

@MainActor
@Suite(.serialized, .uiGate)
struct RenameControllerTests {
    private func makeClient(
        root: URL,
        connection: ScriptedServerConnection,
        capabilities: ServerCapabilities
    ) async throws -> LSPService.LanguageServerType {
        let client = LSPService.LanguageServerType(
            languageId: .swift,
            binary: LanguageServerBinary(execPath: "", args: [], env: nil),
            lspInstance: InitializingServer(
                server: connection,
                initializeParamsProvider: LSPService.LanguageServerType.getInitParams(workspacePath: root.path())
            ),
            lspPid: -1,
            serverCapabilities: capabilities,
            rootPath: root,
            logContainer: LanguageServerLogContainer(languageID: "swift")
        )
        _ = try await client.lspInstance.initializeIfNeeded()
        return client
    }

    private func renameCapabilities() -> ServerCapabilities {
        var capabilities = ScriptedServerConnection.incrementalCapabilities()
        capabilities.renameProvider = .optionB(RenameOptions(prepareProvider: true))
        return capabilities
    }

    private func openNotes(in harness: RenameWindowHarness, directory: URL) throws -> (tab: EditorInstance, url: URL) {
        let url = directory.appending(path: "Notes.txt")
        try "hello world\n".write(to: url, atomically: true, encoding: .utf8)
        EditorLocationNavigation.open(fileURL: url, line: 1, column: 3, workspace: harness.workspace)
        let tab = try #require(harness.workspace.editorManager?.activeEditor.selectedTab)
        return (tab, tab.file.url)
    }

    private func renameParams(_ connection: ScriptedServerConnection) -> [RenameParams] {
        connection.requests.compactMap { request in
            if case let .rename(params, _) = request {
                return params
            }
            return nil
        }
    }

    @Test
    func withoutAnActiveEditorNothingHappens() throws {
        try withTempDir { directory in
            let harness = try RenameWindowHarness.make(in: directory)
            defer { harness.close() }

            #expect(RenameController.present(in: harness.controller) == nil)
            harness.controller.renameSymbol(nil)

            #expect(harness.panels.isEmpty)
        }
    }

    @Test
    func withoutALanguageServerTheMissingServerMessageIsShown() throws {
        try withTempDir { directory in
            let harness = try RenameWindowHarness.make(in: directory)
            defer { harness.close() }
            _ = try openNotes(in: harness, directory: directory)

            #expect(RenameController.present(in: harness.controller) == nil)

            #expect(harness.messagePanels.count == 1)
            #expect(harness.renamePanels.isEmpty)
        }
    }

    @Test
    func theFullFlowPromptsPrefilledAndAppliesTheServersEditToTheOpenDocument() async throws {
        let service = LSPService.shared
        try await withTempDir { directory in
            let harness = try RenameWindowHarness.make(in: directory)
            defer { harness.close() }
            let (tab, url) = try openNotes(in: harness, directory: directory)
            let document = try #require(tab.file.fileDocument)
            let connection = ScriptedServerConnection(capabilities: renameCapabilities())
            let client = try await makeClient(root: directory, connection: connection, capabilities: renameCapabilities())
            try await client.openDocument(document)
            let key = LSPService.ClientKey(.swift, directory.path() + "/")
            service.languageClients[key] = client
            defer { service.languageClients[key] = nil }
            try connection.script(
                .textDocumentPrepareRename,
                RangeWithPlaceholder(range: SyncTestServer.range(0, 0, 5), placeholder: "hello")
            )
            try connection.script(
                .textDocumentRename,
                SyncTestServer.decode(
                    WorkspaceEdit.self,
                    #"{"changes":{"\#(url.lspURI)":[{"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":5}},"newText":"greetings"}]}}"#
                )
            )

            let task = try #require(RenameController.present(in: harness.controller))
            try await eventually { harness.renameModel != nil }
            let model = try #require(harness.renameModel)
            #expect(model.name == "hello")
            model.name = "greetings"
            model.confirm()
            await task.value

            #expect(renameParams(connection).map(\.newName) == ["greetings"])
            #expect(renameParams(connection).map(\.textDocument.uri) == [url.lspURI])
            #expect(renameParams(connection).map(\.position) == [Position(line: 0, character: 2)])
            #expect(document.content?.string == "greetings world\n")
            #expect(harness.messagePanels.isEmpty)
        }
    }

    @Test
    func aNullPrepareResponseShowsTheNotRenameableMessageAndNoPrompt() async throws {
        let service = LSPService.shared
        try await withTempDir { directory in
            let harness = try RenameWindowHarness.make(in: directory)
            defer { harness.close() }
            let (tab, _) = try openNotes(in: harness, directory: directory)
            let document = try #require(tab.file.fileDocument)
            let connection = ScriptedServerConnection(capabilities: renameCapabilities())
            let client = try await makeClient(root: directory, connection: connection, capabilities: renameCapabilities())
            try await client.openDocument(document)
            let key = LSPService.ClientKey(.swift, directory.path() + "/")
            service.languageClients[key] = client
            defer { service.languageClients[key] = nil }

            let task = try #require(RenameController.present(in: harness.controller))
            await task.value

            #expect(harness.renamePanels.isEmpty)
            #expect(harness.messagePanels.count == 1)
            #expect(renameParams(connection).isEmpty)
        }
    }
}
