import AppKit
import CodeEditSourceEditor
import Foundation
import LanguageServerProtocol
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
private final class QuickDocFlowHarness {
    static let mainText = "value = helper()\n"
    static let notesText = "plain notes\n"

    let fixture: LSPServiceFixture
    let files: LSPServiceWorkspace
    let service: LSPService
    let connection: ScriptedServerConnection
    let controller: DreamderWindowController

    var workspace: WorkspaceDocument {
        files.workspace
    }

    var panels: [QuickDocumentationPanel] {
        controller.window?.childWindows?.compactMap { $0 as? QuickDocumentationPanel } ?? []
    }

    var panelModel: QuickDocumentationViewModel? {
        (panels.first?.contentView as? NSHostingView<QuickDocumentationView>)?.rootView.model
    }

    static func make(in directory: URL) async throws -> QuickDocFlowHarness {
        let files = try LSPServiceWorkspace(
            directory: directory,
            files: ["main.py": mainText, "notes.txt": notesText]
        )
        let fixture = LSPServiceFixture()
        let service = fixture.makeService()
        service.openDocument(try files.document("main.py"))
        await service.waitForDocumentOperations()
        let connection = try #require(fixture.created.first?.connection)
        files.workspace.makeWindowControllers()
        let controller = try #require(files.workspace.windowControllers.first as? DreamderWindowController)
        controller.window?.isReleasedWhenClosed = false
        controller.window?.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: false)
        return QuickDocFlowHarness(
            fixture: fixture,
            files: files,
            service: service,
            connection: connection,
            controller: controller
        )
    }

    private init(
        fixture: LSPServiceFixture,
        files: LSPServiceWorkspace,
        service: LSPService,
        connection: ScriptedServerConnection,
        controller: DreamderWindowController
    ) {
        self.fixture = fixture
        self.files = files
        self.service = service
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

    func open(_ name: String, line: Int = 1, column: Int = 11) {
        LSPDefinitionNavigator.open(
            url: files.directory.appending(path: name),
            position: CursorPosition(line: line, column: column),
            in: workspace
        )
    }

    var selectedTab: EditorInstance? {
        workspace.editorManager?.activeEditor.selectedTab
    }

    func scriptHover(_ json: String) throws {
        try connection.script(.textDocumentHover, SyncTestServer.decode(Hover.self, json))
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

@MainActor
@Suite(.serialized, .uiGate)
struct QuickDocumentationFlowCoverageTests {
    private static let escapeKey: UInt16 = 53
    private static let letterKey: UInt16 = 0

    @Test
    func presentShowsTheHoverDocumentationOfTheSymbolUnderTheCaret() async throws {
        try await withTempDir { directory in
            let harness = try await QuickDocFlowHarness.make(in: directory)
            defer { harness.close() }
            harness.open("main.py")
            try harness.scriptHover(
                #"{"contents":{"kind":"markdown","value":"**helper**\n\n```python\ndef helper()\n```"}}"#
            )

            await QuickDocumentationController.present(in: harness.controller, lspService: harness.service)?.value

            let model = try #require(harness.panelModel)
            #expect(model.blocks == [.prose("**helper**"), .code("def helper()")])
            #expect(harness.connection.requestCount(.textDocumentHover) == 1)
        }
    }

    @Test
    func presentReportsMissingDocumentationWhenTheServerHasNoHover() async throws {
        try await withTempDir { directory in
            let harness = try await QuickDocFlowHarness.make(in: directory)
            defer { harness.close() }
            harness.open("main.py")

            await QuickDocumentationController.present(in: harness.controller, lspService: harness.service)?.value

            #expect(harness.panelModel?.blocks == [.plain("No documentation found")])
        }
    }

    @Test
    func presentWithoutAServerExplainsWhatIsNeeded() async throws {
        try await withTempDir { directory in
            let harness = try await QuickDocFlowHarness.make(in: directory)
            defer { harness.close() }
            harness.open("notes.txt")

            let task = QuickDocumentationController.present(in: harness.controller, lspService: nil)

            #expect(task == nil)
            #expect(harness.panelModel?.blocks == [.plain("Quick Documentation needs a language server for this file")])
        }
    }

    @Test
    func presentWithoutAnEditorDoesNothing() async throws {
        try await withTempDir { directory in
            let harness = try await QuickDocFlowHarness.make(in: directory)
            defer { harness.close() }
            harness.controller.workspace = nil

            let task = QuickDocumentationController.present(in: harness.controller, lspService: harness.service)
            harness.controller.showQuickDocumentation(nil)

            #expect(task == nil)
            #expect(harness.panels.isEmpty)
            harness.controller.workspace = harness.workspace
        }
    }

    @Test
    func showingAgainReplacesThePreviousPanelOfTheSameWindow() async throws {
        try await withTempDir { directory in
            let harness = try await QuickDocFlowHarness.make(in: directory)
            defer { harness.close() }

            QuickDocumentationPanelHost.shared.showMessage("first", in: harness.controller)
            let first = try #require(harness.panels.first)
            QuickDocumentationPanelHost.shared.showMessage("second", in: harness.controller)

            #expect(harness.panels.count == 1)
            #expect(harness.panels.first !== first)
            #expect(!first.isVisible)
            #expect(harness.panelModel?.blocks == [.plain("second")])
        }
    }

    @Test
    func modelCloseDismissesThePanel() async throws {
        try await withTempDir { directory in
            let harness = try await QuickDocFlowHarness.make(in: directory)
            defer { harness.close() }
            QuickDocumentationPanelHost.shared.showMessage("docs", in: harness.controller)
            let model = try #require(harness.panelModel)

            model.close()

            #expect(harness.panels.isEmpty)
        }
    }

    @Test
    func escapeClosesAVisiblePanelAndOtherKeysLeaveItOpen() async throws {
        try await withTempDir { directory in
            let harness = try await QuickDocFlowHarness.make(in: directory)
            defer { harness.close() }
            QuickDocumentationPanelHost.shared.showMessage("docs", in: harness.controller)
            let panel = try #require(harness.panels.first)

            NSApp.sendEvent(try harness.keyEvent(Self.letterKey))
            #expect(panel.isVisible)
            #expect(harness.panels.count == 1)

            NSApp.sendEvent(try harness.keyEvent(Self.escapeKey))

            #expect(harness.panels.isEmpty)
            #expect(panel.onClose == nil)
        }
    }

    @Test
    func escapeOnAHiddenPanelForgetsItWithoutClosingIt() async throws {
        try await withTempDir { directory in
            let harness = try await QuickDocFlowHarness.make(in: directory)
            defer { harness.close() }
            QuickDocumentationPanelHost.shared.showMessage("docs", in: harness.controller)
            let panel = try #require(harness.panels.first)
            panel.orderOut(nil)

            NSApp.sendEvent(try harness.keyEvent(Self.escapeKey))

            #expect(!panel.isVisible)
            #expect(panel.onClose != nil)
        }
    }

    @Test
    func movingTheCaretClosesThePanelShownForThatEditor() async throws {
        try await withTempDir { directory in
            let harness = try await QuickDocFlowHarness.make(in: directory)
            defer { harness.close() }
            harness.open("main.py")
            try harness.scriptHover(#"{"contents":{"kind":"plaintext","value":"docs"}}"#)
            await QuickDocumentationController.present(in: harness.controller, lspService: harness.service)?.value
            let tab = try #require(harness.selectedTab)
            #expect(harness.panels.count == 1)
            var line = 2

            try await eventually(timeout: .seconds(30)) {
                line += 1
                tab.cursorPositions = [CursorPosition(line: line, column: 1)]
                return harness.panels.isEmpty
            }
        }
    }

    @Test
    func panelOriginPrefersBelowTheAnchorFlipsAboveAndSurvivesMissingScreens() {
        let size = NSSize(width: 400, height: 200)
        let parent = NSRect(x: 0, y: 0, width: 1200, height: 800)
        let visible = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let roomy = NSRect(x: 100, y: 500, width: 2, height: 16)
        let cramped = NSRect(x: 100, y: 60, width: 2, height: 16)

        func origin(_ anchor: NSRect?, _ visibleFrame: NSRect?) -> NSPoint {
            QuickDocumentationPanel.origin(
                size: size,
                parentFrame: parent,
                anchor: anchor,
                visibleFrame: visibleFrame
            )
        }
        let below = origin(roomy, visible)
        let above = origin(cramped, visible)
        let centered = origin(nil, nil)
        let blindBelow = origin(roomy, nil)
        let blindAbove = origin(NSRect(x: 100, y: 50, width: 2, height: 16), nil)

        #expect(below == NSPoint(x: 100, y: 294))
        #expect(above == NSPoint(x: 100, y: 82))
        #expect(centered == NSPoint(x: 400, y: 508))
        #expect(blindBelow == NSPoint(x: 100, y: 294))
        #expect(blindAbove == NSPoint(x: 100, y: 72))
    }

    @Test
    func hostWithoutAWindowPresentsNothing() {
        let host = QuickDocumentationPanelHost()
        let controller = DreamderWindowController(window: nil, workspace: nil)

        host.showMessage("docs", in: controller)

        let entries = Mirror(reflecting: host).children.first { $0.label == "entries" }
        #expect(entries.map { Mirror(reflecting: $0.value).children.count } == 0)
        #expect(controller.window == nil)
    }

    @Test
    func movingTheCaretDoesNotCloseAPanelThatIsAlreadyHidden() async throws {
        try await withTempDir { directory in
            let harness = try await QuickDocFlowHarness.make(in: directory)
            defer { harness.close() }
            harness.open("main.py")
            try harness.scriptHover(#"{"contents":{"kind":"plaintext","value":"docs"}}"#)
            await QuickDocumentationController.present(in: harness.controller, lspService: harness.service)?.value
            let tab = try #require(harness.selectedTab)
            let panel = try #require(harness.panels.first)
            panel.orderOut(nil)
            var line = 2

            try await eventually(timeout: .seconds(30)) {
                line += 1
                tab.cursorPositions = [CursorPosition(line: line, column: 1)]
                return line > 40
            }

            #expect(!panel.isVisible)
            #expect(panel.onClose != nil)
        }
    }

    @Test
    func escapeForAnEntryWhosePanelIsGoneAndWhoseEntryWasDroppedChangesNothing() async throws {
        try await withTempDir { directory in
            let harness = try await QuickDocFlowHarness.make(in: directory)
            defer { harness.close() }
            let otherWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                styleMask: [.titled],
                backing: .buffered,
                defer: true
            )
            otherWindow.isReleasedWhenClosed = false
            let otherController = DreamderWindowController(window: otherWindow, workspace: nil)
            defer { otherWindow.close() }
            let host = QuickDocumentationPanelHost()

            host.showMessage("first", in: harness.controller)
            weak let weakPanel: QuickDocumentationPanel? = harness.panels.first
            harness.panels.first?.onClose = nil
            harness.panels.first?.close()
            try await eventually { weakPanel == nil }
            host.showMessage("second", in: otherController)
            let secondPanel = try #require(otherWindow.childWindows?.first as? QuickDocumentationPanel)

            NSApp.sendEvent(try harness.keyEvent(Self.escapeKey))
            NSApp.sendEvent(try harness.keyEvent(Self.escapeKey))

            #expect(harness.panels.isEmpty)
            #expect(!secondPanel.isVisible)
            withExtendedLifetime(host) {}
        }
    }
}
