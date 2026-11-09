import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
private final class CommandRunCounter {
    private(set) var runs = 0

    func record() {
        runs += 1
    }
}

extension DreamderWindowControllerCoverageTests {
    func keepVisible(_ panel: SearchPanel) {
        panel.hidesOnDeactivate = false
        panel.orderFront(nil)
    }

    @Test
    func theCommandPaletteOpensClosesAndReopensItsPanel() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            let state = try #require(harness.workspace.commandsPaletteState)

            harness.controller.openCommandPalette(harness.controller)
            let panel = try #require(harness.controller.commandPalettePanel)
            keepVisible(panel)

            #expect(panel.isVisible)
            #expect(harness.window.childWindows?.contains(panel) == true)
            #expect(!state.filteredCommands.isEmpty)

            state.commandQuery = "quick"
            harness.controller.openCommandPalette(harness.controller)

            #expect(!panel.isVisible)
            #expect(state.commandQuery.isEmpty)

            state.commandQuery = "again"
            harness.controller.openCommandPalette(harness.controller)

            #expect(state.commandQuery.isEmpty)
            #expect(harness.controller.commandPalettePanel === panel)
            #expect(harness.window.childWindows?.contains(panel) == true)
        }
    }

    @Test
    func pickingACommandInThePaletteClosesThePanelAndRunsTheCommand() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            harness.controller.openCommandPalette(harness.controller)
            let panel = try #require(harness.controller.commandPalettePanel)
            keepVisible(panel)
            let hosting = try #require(panel.contentView as? NSHostingView<SettingsInjector<QuickActionsView>>)
            let counter = CommandRunCounter()
            let command = Command(id: "probe", title: "Probe") { counter.record() }
            #expect(panel.isVisible)

            hosting.rootView.content.callHandler(command: command)

            #expect(!panel.isVisible)
            #expect(counter.runs == 1)
        }
    }

    @Test
    func closingTheCommandPaletteHidesItsPanel() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            harness.controller.openCommandPalette(harness.controller)
            let panel = try #require(harness.controller.commandPalettePanel)
            keepVisible(panel)
            #expect(panel.isVisible)

            harness.controller.closeCommandPalette()

            #expect(!panel.isVisible)
        }
    }

    @Test
    func theCommandPaletteNeedsAWorkspace() {
        let window = NSWindow()
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let controller = DreamderWindowController(window: window, workspace: nil)

        controller.openCommandPalette(controller)
        controller.closeCommandPalette()

        #expect(controller.commandPalettePanel == nil)
    }

    @Test
    func quickOpenOpensClosesAndReopensItsPanel() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }

            harness.controller.openQuickly(nil)
            let panel = try #require(harness.controller.quickOpenPanel)
            keepVisible(panel)

            #expect(panel.isVisible)
            #expect(harness.window.childWindows?.contains(panel) == true)

            harness.controller.openQuickly(nil)

            #expect(!panel.isVisible)
            #expect(harness.controller.quickOpenPanel === panel)

            harness.controller.openQuickly(nil)

            #expect(harness.controller.quickOpenPanel === panel)
            #expect(harness.window.childWindows?.contains(panel) == true)
        }
    }

    @Test
    func quickOpenNeedsAWorkspace() {
        let window = NSWindow()
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let controller = DreamderWindowController(window: window, workspace: nil)

        controller.openQuickly(nil)
        controller.closeQuickOpen()
        controller.openFromQuickOpen(CEWorkspaceFile(url: URL(filePath: "/tmp/Unused.swift")))

        #expect(controller.quickOpenPanel == nil)
    }

    @Test
    func choosingAFileInQuickOpenOpensItsTabAndClosingHidesThePanel() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            harness.controller.openQuickly(nil)
            let panel = try #require(harness.controller.quickOpenPanel)
            keepVisible(panel)
            let path = directory.appending(path: "One.swift").path(percentEncoded: false)
            let file = try #require(harness.workspace.workspaceFileManager?.getFile(path, createIfNotFound: true))
            #expect(panel.isVisible)

            harness.controller.openFromQuickOpen(file)
            harness.controller.closeQuickOpen()

            #expect(harness.openTabNames == ["One.swift"])
            #expect(!panel.isVisible)
        }
    }

    func editableField(in root: NSView) -> NSTextField? {
        if let field = root as? NSTextField, field.isEditable { return field }
        for subview in root.subviews {
            if let found = editableField(in: subview) { return found }
        }
        return nil
    }

    func hasRow(named name: String, in root: NSView) -> Bool {
        if let field = root as? NSTextField, !field.isEditable, field.stringValue == name { return true }
        return root.subviews.contains { hasRow(named: name, in: $0) }
    }

    @Test
    func submittingInTheQuickOpenPanelOpensTheTabAndHidesThePanel() async throws {
        try await withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            harness.controller.openQuickly(nil)
            let panel = try #require(harness.controller.quickOpenPanel)
            keepVisible(panel)
            let model = try #require(harness.workspace.openQuicklyViewModel)
            let content = try #require(panel.contentView)

            model.query = "One"
            try await eventually(timeout: .seconds(30)) {
                model.searchResults.map(\.fileURL.lastPathComponent) == ["One.swift"]
            }
            try await eventually(timeout: .seconds(30)) {
                content.layoutSubtreeIfNeeded()
                return hasRow(named: "One.swift", in: content)
            }
            let field = try #require(editableField(in: content))
            panel.makeFirstResponder(field)
            if field.currentEditor() == nil {
                field.selectText(nil)
            }
            let editor = try #require(field.currentEditor() as? NSTextView)

            editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))

            #expect(harness.openTabNames == ["One.swift"])
            #expect(!panel.isVisible)
            #expect(model.query.isEmpty)
        }
    }
}
