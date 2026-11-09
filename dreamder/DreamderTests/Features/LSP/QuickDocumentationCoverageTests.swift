import AppKit
import CodeEditSourceEditor
import Foundation
import LanguageServerProtocol
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
private final class CloseCounter {
    var count = 0
}

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
}

@MainActor
@Suite(.uiGate)
struct QuickDocumentationPanelCoverageTests {
    private func makeParent(in visible: NSRect) -> NSWindow {
        let parent = NSWindow(
            contentRect: NSRect(x: visible.minX + 100, y: visible.minY + 100, width: 800, height: 600),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        parent.isReleasedWhenClosed = false
        return parent
    }

    private func visibleFrame() throws -> NSRect {
        try #require(NSScreen.main).visibleFrame
    }

    @Test
    func panelNeverBecomesKeyOrMain() {
        let panel = QuickDocumentationPanel(size: NSSize(width: 300, height: 100))

        #expect(!panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
    }

    @Test
    func panelWithoutAnchorIsCenteredNearTheTopOfItsParent() throws {
        let parent = makeParent(in: try visibleFrame())
        defer { parent.close() }
        let panel = QuickDocumentationPanel(size: NSSize(width: 400, height: 200))

        panel.place(in: parent, beside: nil)

        #expect(panel.frame.size == NSSize(width: 400, height: 200))
        #expect(panel.frame.midX == parent.frame.midX)
        #expect(panel.frame.maxY == parent.frame.maxY - 92)
    }

    @Test
    func panelIsPlacedBelowTheAnchorWhenThereIsRoom() throws {
        let visible = try visibleFrame()
        let parent = makeParent(in: visible)
        defer { parent.close() }
        let panel = QuickDocumentationPanel(size: NSSize(width: 400, height: 200))
        let anchor = NSRect(x: visible.minX + 150, y: visible.minY + 500, width: 4, height: 18)

        panel.place(in: parent, beside: anchor)

        #expect(panel.frame.minX == anchor.minX)
        #expect(panel.frame.maxY == anchor.minY - 6)
    }

    @Test
    func panelIsPlacedAboveTheAnchorWhenTheScreenBottomIsTooClose() throws {
        let visible = try visibleFrame()
        let parent = makeParent(in: visible)
        defer { parent.close() }
        let panel = QuickDocumentationPanel(size: NSSize(width: 400, height: 200))
        let anchor = NSRect(x: visible.minX + 150, y: visible.minY + 20, width: 4, height: 18)

        panel.place(in: parent, beside: anchor)

        #expect(panel.frame.minY == anchor.maxY + 6)
    }

    @Test
    func panelIsClampedInsideTheVisibleScreenArea() throws {
        let visible = try visibleFrame()
        let parent = makeParent(in: visible)
        defer { parent.close() }
        let panel = QuickDocumentationPanel(size: NSSize(width: 400, height: 200))

        panel.place(in: parent, beside: NSRect(x: visible.maxX + 500, y: visible.minY + 500, width: 4, height: 18))
        #expect(panel.frame.maxX == visible.maxX - 8)

        panel.place(in: parent, beside: NSRect(x: visible.minX - 500, y: visible.minY + 500, width: 4, height: 18))
        #expect(panel.frame.minX == visible.minX + 8)

        panel.place(in: parent, beside: NSRect(x: visible.minX + 150, y: visible.maxY + 500, width: 4, height: 18))
        #expect(panel.frame.maxY == visible.maxY - 8)
    }

    @Test
    func closingThePanelDetachesItAndRunsTheCloseHandlerOnce() throws {
        let parent = makeParent(in: try visibleFrame())
        defer { parent.close() }
        let panel = QuickDocumentationPanel(size: NSSize(width: 300, height: 100))
        let counter = CloseCounter()
        panel.onClose = { counter.count += 1 }
        parent.addChildWindow(panel, ordered: .above)

        panel.close()
        panel.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: panel))

        #expect(counter.count == 1)
        #expect(panel.onClose == nil)
        #expect(parent.childWindows?.contains(panel) != true)
    }
}

@MainActor
@Suite(.uiGate)
struct QuickDocumentationViewCoverageTests {
    private func host(_ model: QuickDocumentationViewModel) -> HostedView {
        HostedViewFixture.host(size: model.size) {
            QuickDocumentationView(model: model)
        }
    }

    @Test
    func everyBlockKindRendersVisibleContent() async throws {
        let markdown = "**Int** — a `number` with [link](https://example.com)\n\n```swift\nlet value = 1\n```\n\nTail."
        let models = [
            QuickDocumentationViewModel(content: QuickDocumentationContent(text: markdown, isMarkdown: true)),
            QuickDocumentationViewModel(content: QuickDocumentationContent(text: "Int\nA number", isMarkdown: false)),
            QuickDocumentationViewModel(message: "No documentation found")
        ]

        for model in models {
            let hosted = host(model)
            defer { hosted.close() }
            try await hosted.settle()
            #expect(hosted.renders())
        }
    }

    @Test
    func differentContentRendersDifferently() async throws {
        let prose = host(QuickDocumentationViewModel(message: "Int"))
        let code = host(QuickDocumentationViewModel(
            content: QuickDocumentationContent(text: "```swift\nfunc run() -> Int\n```", isMarkdown: true)
        ))
        defer {
            prose.close()
            code.close()
        }
        try await prose.settle()
        try await code.settle()

        #expect(HostedView.pixelsDiffer(prose.snapshot(), code.snapshot()))
    }

    @Test
    func closingTheModelCallsTheDismissHandlerWhenOneIsSet() {
        let model = QuickDocumentationViewModel(message: "docs")
        let counter = CloseCounter()

        model.close()
        model.dismiss = { counter.count += 1 }
        model.close()

        #expect(counter.count == 1)
    }
}
