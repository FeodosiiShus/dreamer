import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct FileCommandsACoverageTests {
    @MainActor
    private final class DocumentControllerRecorder: AppDocumentControlling {
        var documents: [NSDocument] = []
        private(set) var newDocumentCalls = 0
        private(set) var openPanelCalls = 0

        func openDocument(
            withContentsOf url: URL,
            display displayDocument: Bool,
            completionHandler: @escaping (NSDocument?, Bool, (any Error)?) -> Void
        ) {}

        func openDocument(_ sender: Any?) {
            openPanelCalls += 1
        }

        func newDocument(_ sender: Any?) {
            newDocumentCalls += 1
        }

        func closeAllDocuments(
            withDelegate delegate: Any?,
            didCloseAllSelector: Selector?,
            contextInfo: UnsafeMutableRawPointer?
        ) {}
    }

    @Test
    func newAndOpenButtonsGoThroughTheDocumentController() throws {
        let controller = DocumentControllerRecorder()
        let menu = CommandsACoverageSupport.host {
            FileCommands.DocumentButtons(documentController: controller)
        }
        defer { menu.close() }

        try menu.click(0)
        #expect(controller.newDocumentCalls == 1)
        #expect(controller.openPanelCalls == 0)

        try menu.click(1)
        #expect(controller.newDocumentCalls == 1)
        #expect(controller.openPanelCalls == 1)
    }

    @Test
    func closeTabAndCloseEditorSendToTheResponderThatHandlesThem() throws {
        let recorder = CommandsACoverageRecorder()
        let window = CommandsACoverageWindow.make()
        let menu = CommandsACoverageSupport.host {
            FileCommands.CloseButtons(responderForAction: { _ in recorder }, keyWindow: { window })
        }
        defer { menu.close() }

        try menu.click(0)
        try menu.click(1)

        #expect(recorder.received == ["closeCurrentTab(_:)", "closeActiveEditor(_:)"])
        #expect(window.performCloseCalls == 0)
    }

    @Test
    func closeTabAndCloseEditorFallBackToClosingTheKeyWindow() throws {
        let window = CommandsACoverageWindow.make()
        let menu = CommandsACoverageSupport.host {
            FileCommands.CloseButtons(responderForAction: { _ in nil }, keyWindow: { window })
        }
        defer { menu.close() }

        try menu.click(0)
        try menu.click(1)

        #expect(window.performCloseCalls == 2)
    }

    @Test
    func closeWindowClosesTheKeyWindowAndCloseWorkspaceIsDisabledOutsideWorkspaceWindows() throws {
        let window = CommandsACoverageWindow.make()
        let menu = CommandsACoverageSupport.host {
            FileCommands.CloseButtons(responderForAction: { _ in nil }, keyWindow: { window })
        }
        defer { menu.close() }

        try menu.click(2)
        try menu.click(3)

        #expect(menu.titles.last == "Close Workspace")
        #expect(menu.enabledStates == [true, true, true, false])
        #expect(window.performCloseCalls == 1)
    }

    @Test
    func closeWorkspaceClosesTheKeyWindowOfAWorkspaceController() throws {
        let window = CommandsACoverageWindow.make()
        let controller = DreamderWindowController(window: window, workspace: nil)
        let menu = CommandsACoverageSupport.host {
            FileCommands.CloseButtons(responderForAction: { _ in nil }, keyWindow: { window })
        }
        defer { menu.close() }

        try menu.click(3)

        #expect(window.windowController === controller)
        #expect(window.performCloseCalls == 1)
    }

    @Test
    func closeTerminalRemovesTheSelectedTerminals() throws {
        try withTempDir { directory in
            let model = UtilityAreaViewModel()
            model.addTerminal(rootURL: directory)
            model.addTerminal(rootURL: directory)
            let first = try #require(model.terminals.first)
            let menu = CommandsACoverageSupport.host {
                FileCommands.CloseTerminalButton(utilityAreaViewModel: model)
            }
            defer { menu.close() }

            try menu.click(0)

            #expect(model.terminals.map(\.id) == [first.id])
            #expect(model.selectedTerminals == [first.id])
        }
    }

    @Test
    func closeTerminalIsAbsentWithoutAUtilityAreaModel() {
        let menu = CommandsACoverageSupport.host {
            FileCommands.CloseTerminalButton(utilityAreaViewModel: nil)
        }
        defer { menu.close() }

        #expect(menu.items.isEmpty)
    }

    @Test
    func workspaceSettingsAndSaveSendTheirActions() throws {
        let recorder = CommandsACoverageRecorder()
        let menu = CommandsACoverageSupport.host {
            FileCommands.WorkspaceButtons(isWorkspaceSettingsEnabled: true, target: recorder)
        }
        defer { menu.close() }

        try menu.click(0)
        try menu.click(1)
        try menu.click(2)

        #expect(menu.titles == ["Workspace Settings", "Trust Project\u{2026}", "Save"])
        #expect(recorder.received == ["openWorkspaceSettings(_:)", "trustProject(_:)", "saveDocument(_:)"])
    }

    @Test
    func workspaceSettingsIsDisabledWithoutAWorkspace() throws {
        let recorder = CommandsACoverageRecorder()
        let menu = CommandsACoverageSupport.host {
            FileCommands.WorkspaceButtons(isWorkspaceSettingsEnabled: false, target: recorder)
        }
        defer { menu.close() }

        try menu.click(0)
        try menu.click(1)
        try menu.click(2)

        #expect(menu.titles.first == "Workspace Settings")
        #expect(menu.enabledStates == [false, false, true])
        #expect(recorder.received == ["saveDocument(_:)"])
    }

    @Test
    func commandBodyBuilds() {
        _ = FileCommands().body
    }
}
