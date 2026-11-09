import AppKit
import CodeEditSourceEditor
import Foundation
import LanguageServerProtocol
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
final class UsagesFlowHarness {
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

enum UsagesFlowHarnessError: Error {
    case notReady
}
