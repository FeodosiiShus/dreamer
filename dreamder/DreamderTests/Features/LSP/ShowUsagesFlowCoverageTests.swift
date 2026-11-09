import AppKit
import CodeEditSourceEditor
import Foundation
import LanguageServerProtocol
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
private final class UsagesFlowHarness {
    static let mainText = "value = helper()\n\nother = value\n"
    static let helperText = "def helper():\n    return 1\n"
    static let otherText = "helper()\n"
    static let notesText = "plain notes\n"

    let fixture: LSPServiceFixture
    let files: LSPServiceWorkspace
    let service: LSPService
    let mainDocument: CodeFileDocument
    let connection: ScriptedServerConnection
    let controller: DreamderWindowController

    var workspace: WorkspaceDocument {
        files.workspace
    }

    var panels: [ShowUsagesPanel] {
        controller.window?.childWindows?.compactMap { $0 as? ShowUsagesPanel } ?? []
    }

    var panelModel: ShowUsagesViewModel? {
        (panels.first?.contentView as? NSHostingView<ShowUsagesView>)?.rootView.model
    }

    static func make(in directory: URL) async throws -> UsagesFlowHarness {
        let files = try LSPServiceWorkspace(
            directory: directory,
            files: [
                "main.py": mainText,
                "helper.py": helperText,
                "other.py": otherText,
                "notes.txt": notesText,
                "closed.py": "closed()\n"
            ]
        )
        let fixture = LSPServiceFixture()
        let service = fixture.makeService()
        let mainDocument = try files.document("main.py")
        service.openDocument(mainDocument)
        await service.waitForDocumentOperations()
        let connection = try #require(fixture.created.first?.connection)
        files.workspace.makeWindowControllers()
        let controller = try #require(files.workspace.windowControllers.first as? DreamderWindowController)
        controller.window?.isReleasedWhenClosed = false
        controller.window?.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: false)
        return UsagesFlowHarness(
            fixture: fixture,
            files: files,
            service: service,
            mainDocument: mainDocument,
            connection: connection,
            controller: controller
        )
    }

    private init(
        fixture: LSPServiceFixture,
        files: LSPServiceWorkspace,
        service: LSPService,
        mainDocument: CodeFileDocument,
        connection: ScriptedServerConnection,
        controller: DreamderWindowController
    ) {
        self.fixture = fixture
        self.files = files
        self.service = service
        self.mainDocument = mainDocument
        self.connection = connection
        self.controller = controller
    }

    func close() {
        for child in controller.window?.childWindows ?? [] {
            child.close()
        }
        controller.window?.close()
        files.close()
    }

    func url(_ name: String) -> URL {
        files.directory.appending(path: name)
    }

    func open(_ name: String, line: Int = 1, column: Int = 1) {
        LSPDefinitionNavigator.open(
            url: url(name),
            position: CursorPosition(line: line, column: column),
            in: workspace
        )
    }

    func tab(_ name: String) -> EditorInstance? {
        workspace.editorManager?.activeEditor.tabs.first { $0.file.url.lastPathComponent == name }
    }

    func location(_ name: String, _ line: Int, _ start: Int, _ end: Int) -> Location {
        Location(
            uri: files.uri(name),
            range: LSPRange(
                start: Position(line: line, character: start),
                end: Position(line: line, character: end)
            )
        )
    }

    func readyContext(line: Int, column: Int) throws -> LSPEditorContext {
        open("main.py", line: line, column: column)
        let result = LSPEditorContextResolver.resolve(workspace: workspace, lspService: service)
        guard case .ready(let context) = result else {
            throw UsagesFlowHarnessError.notReady
        }
        return context
    }

    func row(for name: String, line: Int, column: Int) -> LSPUsageRow {
        LSPUsageRow(
            uri: files.uri(name),
            fileURL: url(name),
            fileName: name,
            fileIconName: IntelliJIcon.fileIcon(for: name),
            relativeDirectory: "",
            line: line,
            column: column,
            lineText: "text",
            matchRange: nil
        )
    }

    func keyEvent(_ code: UInt16) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: code
        ))
    }
}

private enum UsagesFlowHarnessError: Error {
    case notReady
}

@MainActor
@Suite(.serialized, .uiGate)
struct ShowUsagesFlowCoverageTests {
    @Test
    func resolverBuildsTheContextFromTheSelectedTabAndTheOwningServer() async throws {
        try await withTempDir { directory in
            let harness = try await UsagesFlowHarness.make(in: directory)
            defer { harness.close() }

            let context = try harness.readyContext(line: 1, column: 11)

            #expect(context.fileURL.lastPathComponent == "main.py")
            #expect(context.documentURI == context.fileURL.lspURI)
            #expect(context.position == Position(line: 0, character: 10))
            #expect(context.documentText == UsagesFlowHarness.mainText)
            #expect(context.lineText == "value = helper()")
            #expect(context.symbol == "helper")
            #expect(context.client === harness.service.languageClient(forDocument: harness.url("main.py")))
        }
    }

    @Test
    func resolverClampsTheCaretAndYieldsAnEmptySymbolOnBlankLines() async throws {
        try await withTempDir { directory in
            let harness = try await UsagesFlowHarness.make(in: directory)
            defer { harness.close() }

            let blank = try harness.readyContext(line: 2, column: 1)
            let beyondEnd = try harness.readyContext(line: 99, column: 1)

            #expect(blank.lineText.isEmpty)
            #expect(blank.symbol.isEmpty)
            #expect(beyondEnd.position == Position(line: 98, character: 0))
            #expect(beyondEnd.lineText.isEmpty)
        }
    }

    @Test
    func resolverReportsMissingServerWhenNoServiceOwnsTheFile() async throws {
        try await withTempDir { directory in
            let harness = try await UsagesFlowHarness.make(in: directory)
            defer { harness.close() }
            harness.open("notes.txt")
            let idleService = LSPServiceFixture().makeService()

            let withoutService = LSPEditorContextResolver.resolve(workspace: harness.workspace, lspService: nil)
            let withIdleService = LSPEditorContextResolver.resolve(workspace: harness.workspace, lspService: idleService)
            let notesWithServer = LSPEditorContextResolver.resolve(workspace: harness.workspace, lspService: harness.service)

            guard case .missingServer = withoutService, case .missingServer = withIdleService,
                  case .missingServer = notesWithServer else {
                Issue.record("expected a missing server for every service without the file")
                return
            }
        }
    }

    @Test
    func resolverIsUnavailableWithoutAWorkspaceOrSelectedTab() async throws {
        try await withTempDir { directory in
            let harness = try await UsagesFlowHarness.make(in: directory)
            defer { harness.close() }
            let emptyDirectory = directory.appending(path: "empty", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: emptyDirectory, withIntermediateDirectories: true)
            let emptyWorkspace = try LSPServiceWorkspace(directory: emptyDirectory, files: [:])
            defer { emptyWorkspace.close() }
            #expect(emptyWorkspace.workspace.editorManager?.activeEditor.selectedTab == nil)

            let withoutWorkspace = LSPEditorContextResolver.resolve(workspace: nil, lspService: harness.service)
            let withoutTab = LSPEditorContextResolver.resolve(
                workspace: emptyWorkspace.workspace,
                lspService: harness.service
            )

            guard case .unavailable = withoutWorkspace, case .unavailable = withoutTab else {
                Issue.record("expected unavailable without a workspace or a selected tab")
                return
            }
        }
    }

    @Test
    func documentTextPrefersTheOpenDocumentAndFallsBackToTheFileOnDisk() async throws {
        try await withTempDir { directory in
            let harness = try await UsagesFlowHarness.make(in: directory)
            defer { harness.close() }
            harness.open("main.py")
            let tab = try #require(harness.tab("main.py"))
            #expect(LSPEditorContextResolver.documentText(for: tab) == UsagesFlowHarness.mainText)

            tab.file.fileDocument = harness.mainDocument
            harness.files.setText("main.py", "edited = 1\n")
            #expect(LSPEditorContextResolver.documentText(for: tab) == "edited = 1\n")

            let ghost = EditorInstance(
                workspace: nil,
                file: CEWorkspaceFile(url: harness.url("ghost.py"))
            )
            #expect(LSPEditorContextResolver.documentText(for: ghost) == nil)
        }
    }

    @Test
    func loaderWithoutReferencesYieldsNoRows() async throws {
        try await withTempDir { directory in
            let harness = try await UsagesFlowHarness.make(in: directory)
            defer { harness.close() }
            let context = try harness.readyContext(line: 1, column: 11)

            let rows = await LSPUsagesLoader.rows(for: context)

            #expect(rows.isEmpty)
            #expect(harness.connection.requestCount(.textDocumentReferences) == 1)
        }
    }

    @Test
    func loaderReadsTextFromTheContextOpenTabsAndDiskAndSkipsForeignUris() async throws {
        try await withTempDir { directory in
            let harness = try await UsagesFlowHarness.make(in: directory)
            defer { harness.close() }
            harness.open("other.py")
            harness.open("notes.txt")
            let otherTab = try #require(harness.tab("other.py"))
            let otherDocument = try harness.files.document("other.py")
            harness.files.setText("other.py", "changed()\n")
            otherTab.file.fileDocument = otherDocument
            harness.open("helper.py")
            let context = try harness.readyContext(line: 1, column: 11)
            try harness.connection.script(
                .textDocumentReferences,
                [
                    harness.location("main.py", 0, 8, 14),
                    harness.location("helper.py", 0, 4, 10),
                    harness.location("other.py", 0, 0, 7),
                    harness.location("ghost.py", 0, 0, 3),
                    harness.location("closed.py", 0, 0, 6),
                    Location(
                        uri: "untitled:Scratch",
                        range: LSPRange(start: Position(line: 0, character: 0), end: Position(line: 0, character: 1))
                    )
                ]
            )

            let rows = await LSPUsagesLoader.rows(for: context)

            #expect(rows.map(\.fileName) == ["closed.py", "ghost.py", "helper.py", "main.py", "other.py"])
            #expect(rows.map(\.lineText) == ["closed()", "", "def helper():", "value = helper()", "changed()"])
            #expect(rows.map(\.matchRange) == [
                NSRange(location: 0, length: 6),
                nil,
                NSRange(location: 4, length: 6),
                NSRange(location: 8, length: 6),
                NSRange(location: 0, length: 7)
            ])
            #expect(rows.map(\.displayLine) == [1, 1, 1, 1, 1])
            withExtendedLifetime(otherDocument) {}
        }
    }

    @Test
    func presentingUsagesShowsThePopulatedPanel() async throws {
        try await withTempDir { directory in
            let harness = try await UsagesFlowHarness.make(in: directory)
            defer { harness.close() }
            harness.open("main.py", line: 1, column: 11)
            try harness.connection.script(
                .textDocumentReferences,
                [harness.location("main.py", 0, 8, 14), harness.location("main.py", 2, 8, 13)]
            )

            let task = ShowUsagesController.present(in: harness.controller, lspService: harness.service)
            await task?.value

            let model = try #require(harness.panelModel)
            #expect(task != nil)
            #expect(model.headerTitle == "Usages of helper")
            #expect(model.rows.map(\.lineText) == ["value = helper()", "other = value"])
            #expect(harness.panels.count == 1)
        }
    }

    @Test
    func presentingUsagesWithoutResultsNamesTheSymbolInTheMessage() async throws {
        try await withTempDir { directory in
            let harness = try await UsagesFlowHarness.make(in: directory)
            defer { harness.close() }
            harness.open("main.py", line: 1, column: 11)

            await ShowUsagesController.present(in: harness.controller, lspService: harness.service)?.value

            let model = try #require(harness.panelModel)
            #expect(model.message == "No usages found for 'helper'")
        }
    }

    @Test
    func presentingUsagesWithoutResultsOnABlankLineUsesTheGenericMessage() async throws {
        try await withTempDir { directory in
            let harness = try await UsagesFlowHarness.make(in: directory)
            defer { harness.close() }
            harness.open("main.py", line: 2, column: 1)

            await ShowUsagesController.present(in: harness.controller, lspService: harness.service)?.value

            #expect(harness.panelModel?.message == "No usages found")
        }
    }

    @Test
    func presentingUsagesWithoutAServerExplainsWhatIsNeeded() async throws {
        try await withTempDir { directory in
            let harness = try await UsagesFlowHarness.make(in: directory)
            defer { harness.close() }
            harness.open("notes.txt")

            let task = ShowUsagesController.present(in: harness.controller, lspService: nil)

            #expect(task == nil)
            #expect(harness.panelModel?.message == "Show Usages needs a language server for this file")
        }
    }

    @Test
    func presentingUsagesWithoutAnEditorDoesNothing() async throws {
        try await withTempDir { directory in
            let harness = try await UsagesFlowHarness.make(in: directory)
            defer { harness.close() }
            harness.controller.workspace = nil

            let task = ShowUsagesController.present(in: harness.controller, lspService: harness.service)

            #expect(task == nil)
            #expect(harness.panels.isEmpty)
            harness.controller.workspace = harness.workspace
        }
    }

    @Test
    func showAndFindUsagesActionsPresentThePopupForTheActiveEditor() async throws {
        try await withTempDir { directory in
            let harness = try await UsagesFlowHarness.make(in: directory)
            defer { harness.close() }
            harness.open("notes.txt")

            harness.controller.showUsages(nil)
            let first = try #require(harness.panels.first)
            harness.controller.findUsages(nil)

            #expect(harness.panels.count == 1)
            #expect(harness.panels.first !== first)
            #expect(harness.panelModel?.isMessage == true)
        }
    }

    @Test
    func hostShowsRowsAndReplacesThePreviousPanelOfTheSameWindow() async throws {
        try await withTempDir { directory in
            let harness = try await UsagesFlowHarness.make(in: directory)
            defer { harness.close() }
            let rows = [harness.row(for: "helper.py", line: 0, column: 4), harness.row(for: "main.py", line: 2, column: 8)]

            ShowUsagesPanelHost.shared.show(rows: rows, symbol: "helper", in: harness.controller)
            let first = try #require(harness.panels.first)
            ShowUsagesPanelHost.shared.show(rows: rows, symbol: "helper", in: harness.controller)

            #expect(harness.panels.count == 1)
            #expect(harness.panels.first !== first)
            #expect(!first.isVisible)
            #expect(harness.panelModel?.rows == rows)
            #expect(harness.panels.first?.frame.width == 620)
        }
    }

    @Test
    func keyboardNavigatesWrapsAndEscapeClosesThePanel() async throws {
        try await withTempDir { directory in
            let harness = try await UsagesFlowHarness.make(in: directory)
            defer { harness.close() }
            let rows = [harness.row(for: "helper.py", line: 0, column: 4), harness.row(for: "main.py", line: 2, column: 8)]
            ShowUsagesPanelHost.shared.show(rows: rows, symbol: "helper", in: harness.controller)
            let panel = try #require(harness.panels.first)
            let model = try #require(harness.panelModel)

            panel.sendEvent(try harness.keyEvent(125))
            #expect(model.selectedIndex == 1)
            panel.sendEvent(try harness.keyEvent(125))
            #expect(model.selectedIndex == 0)
            panel.sendEvent(try harness.keyEvent(126))
            #expect(model.selectedIndex == 1)

            panel.sendEvent(try harness.keyEvent(53))

            #expect(harness.panels.isEmpty)
        }
    }

    @Test
    func returnOpensTheSelectedUsageInTheEditorAndClosesThePanel() async throws {
        try await withTempDir { directory in
            let harness = try await UsagesFlowHarness.make(in: directory)
            defer { harness.close() }
            let rows = [harness.row(for: "main.py", line: 0, column: 0), harness.row(for: "helper.py", line: 1, column: 4)]
            ShowUsagesPanelHost.shared.show(rows: rows, symbol: "helper", in: harness.controller)
            let panel = try #require(harness.panels.first)

            panel.sendEvent(try harness.keyEvent(125))
            panel.sendEvent(try harness.keyEvent(36))

            let selected = try #require(harness.workspace.editorManager?.activeEditor.selectedTab)
            #expect(selected.file.url.lastPathComponent == "helper.py")
            #expect(selected.cursorPositions.first?.start.line == 2)
            #expect(selected.cursorPositions.first?.start.column == 5)
            #expect(harness.panels.isEmpty)
        }
    }

    @Test
    func openingAUsageAfterTheWorkspaceIsGoneOnlyClosesThePanel() async throws {
        try await withTempDir { directory in
            let harness = try await UsagesFlowHarness.make(in: directory)
            defer { harness.close() }
            harness.open("main.py")
            ShowUsagesPanelHost.shared.show(
                rows: [harness.row(for: "helper.py", line: 0, column: 0)],
                symbol: "helper",
                in: harness.controller
            )
            let model = try #require(harness.panelModel)
            harness.controller.workspace = nil

            model.activate()

            #expect(harness.panels.isEmpty)
            #expect(harness.workspace.editorManager?.activeEditor.selectedTab?.file.url.lastPathComponent == "main.py")
            harness.controller.workspace = harness.workspace
        }
    }

    @Test
    func losingKeyStatusClosesThePanelAndRunsItsCloseHandler() async throws {
        try await withTempDir { directory in
            let harness = try await UsagesFlowHarness.make(in: directory)
            defer { harness.close() }
            ShowUsagesPanelHost.shared.showMessage("No usages found", in: harness.controller)
            let panel = try #require(harness.panels.first)

            panel.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: panel))

            #expect(harness.panels.isEmpty)
            #expect(panel.onClose == nil)
        }
    }

    @Test
    func modelCloseDismissesThePanelAndRestoresTheParentFirstResponder() async throws {
        try await withTempDir { directory in
            let harness = try await UsagesFlowHarness.make(in: directory)
            defer { harness.close() }
            let window = try #require(harness.controller.window)
            let responderBefore = window.firstResponder
            ShowUsagesPanelHost.shared.showMessage("No usages found", in: harness.controller)
            let model = try #require(harness.panelModel)

            model.close()

            #expect(harness.panels.isEmpty)
            #expect(window.firstResponder === responderBefore)
        }
    }
}
