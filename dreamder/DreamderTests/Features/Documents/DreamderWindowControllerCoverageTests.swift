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

@MainActor
@Suite(.serialized, .uiGate)
struct DreamderWindowControllerCoverageTests {
    @MainActor
    private struct Harness {
        let directory: URL
        let workspace: WorkspaceDocument
        let controller: DreamderWindowController
        let window: NSWindow

        var manager: EditorManager? { workspace.editorManager }

        var openTabNames: [String] {
            manager?.activeEditor.tabs.map(\.file.name) ?? []
        }

        func openTab(_ name: String) throws {
            let path = directory.appending(path: name).path(percentEncoded: false)
            let file = try #require(workspace.workspaceFileManager?.getFile(path, createIfNotFound: true))
            manager?.openTab(item: file)
        }

        func close() {
            for child in window.childWindows ?? [] {
                child.close()
            }
            window.close()
            workspace.close()
        }
    }

    private func makeHarness(in directory: URL, files: [String] = ["One.swift"]) throws -> Harness {
        for name in files {
            try "let value = 1\n".write(to: directory.appending(path: name), atomically: true, encoding: .utf8)
        }
        let workspace = WorkspaceDocument()
        try workspace.read(from: directory, ofType: "")
        workspace.makeWindowControllers()
        let controller = try #require(workspace.windowControllers.first as? DreamderWindowController)
        let window = try #require(controller.window)
        window.isReleasedWhenClosed = false
        window.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: false)
        window.orderFront(nil)
        return Harness(directory: directory, workspace: workspace, controller: controller, window: window)
    }

    @Test
    func aControllerWithoutAWindowKeepsTheWorkspaceButHostsNothing() {
        let workspace = WorkspaceDocument()

        let controller = DreamderWindowController(window: nil, workspace: workspace)

        #expect(controller.workspace === workspace)
        #expect(controller.workspaceHostingController == nil)
        #expect(controller.documentEditedObservation != nil)
    }

    @Test
    func aWorkspaceWithoutItsManagersLeavesTheWindowWithoutContent() {
        let window = NSWindow()
        window.isReleasedWhenClosed = false
        defer { window.close() }

        let controller = DreamderWindowController(window: window, workspace: WorkspaceDocument())

        #expect(controller.workspaceHostingController == nil)
        #expect(window.contentViewController == nil)
        #expect(window.delegate === controller)
        #expect(window.toolbar == nil)
    }

    @Test
    func aWorkspaceWindowIsTitledTabbedHostedAndGivenAToolbar() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }

            #expect(harness.window.title == directory.lastPathComponent)
            #expect(harness.window.tabbingIdentifier == "dreamder.workspace")
            #expect(harness.window.tabbingMode == .preferred)
            #expect(harness.controller.workspaceHostingController != nil)
            #expect(harness.window.toolbar?.identifier == "DreamderMainToolbar")
            #expect(!harness.controller.toolbarCollapsed)
        }
    }

    @Test
    func aWorkspaceWithAStoredCollapsedToolbarOpensWithoutOne() throws {
        try withTempDir { directory in
            let workspace = WorkspaceDocument()
            try workspace.read(from: directory, ofType: "")
            workspace.addToWorkspaceState(key: .toolbarCollapsed, value: true)
            workspace.makeWindowControllers()
            let controller = try #require(workspace.windowControllers.first as? DreamderWindowController)
            let window = try #require(controller.window)
            window.isReleasedWhenClosed = false
            defer {
                window.close()
                workspace.close()
            }

            #expect(controller.toolbarCollapsed)
            #expect(window.toolbar == nil)
            #expect(window.titleVisibility == .visible)
        }
    }

    private func keepVisible(_ panel: SearchPanel) {
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

    @Test
    func searchNavigatorShowsTheFindToolWindowAndFocusesItsField() async throws {
        try await withTempDir { directory in
            let workspace = WorkspaceDocument()
            try workspace.read(from: directory, ofType: "")
            defer { workspace.close() }
            let controller = DreamderWindowController(window: nil, workspace: workspace)
            workspace.toolWindowManager.hideAll()

            controller.openSearchNavigator()

            #expect(workspace.toolWindowManager.isVisible(.find))
            try await eventually(timeout: .seconds(30)) {
                workspace.searchState?.shouldFocusSearchField == true
            }
        }
    }

    @Test
    func searchNavigatorNeedsAWorkspace() {
        let window = NSWindow()
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let controller = DreamderWindowController(window: window, workspace: nil)

        controller.openSearchNavigator(nil)

        #expect(controller.workspace == nil)
    }

    @Test
    func closingTheCurrentTabClosesTheSelectedTab() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            try harness.openTab("One.swift")

            harness.controller.closeCurrentTab(harness.controller)

            #expect(harness.openTabNames.isEmpty)
        }
    }

    @Test
    func closingTheCurrentTabDoesNothingWhileASearchPanelIsOpen() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            try harness.openTab("One.swift")
            harness.controller.openQuickly(nil)
            keepVisible(try #require(harness.controller.quickOpenPanel))

            harness.controller.closeCurrentTab(harness.controller)

            #expect(harness.openTabNames == ["One.swift"])

            harness.controller.closeQuickOpen()
            harness.controller.closeCurrentTab(harness.controller)

            #expect(harness.openTabNames.isEmpty)
        }
    }

    @Test
    func closingTheCurrentTabOfAnEmptyEditorClosesThatEditorWhenOthersExist() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            try harness.openTab("One.swift")
            harness.controller.splitEditorRight(nil)
            let manager = try #require(harness.manager)
            #expect(manager.flattenedEditors.count == 2)

            harness.controller.closeCurrentTab(harness.controller)
            #expect(manager.flattenedEditors.count == 2)
            harness.controller.closeCurrentTab(harness.controller)

            #expect(manager.flattenedEditors.count == 1)
        }
    }

    @Test
    func closingTheLastEditorClosesTheWindowAndReleasesTheWorkspace() async throws {
        try await withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }

            harness.controller.closeActiveEditor(harness.controller)

            try await eventually(timeout: .seconds(30)) { harness.controller.workspace == nil }
            #expect(!harness.window.isVisible)
        }
    }

    @Test
    func closingTheWindowReleasesEverythingTheControllerHolds() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            harness.controller.openQuickly(nil)
            harness.controller.openCommandPalette(harness.controller)
            let settingsWindow = NSWindow()
            settingsWindow.isReleasedWhenClosed = false
            settingsWindow.orderFront(nil)
            harness.controller.workspaceSettingsWindow = settingsWindow
            #expect(settingsWindow.isVisible)

            harness.controller.windowWillClose(Notification(name: NSWindow.willCloseNotification))

            #expect(harness.controller.workspace == nil)
            #expect(harness.controller.quickOpenPanel == nil)
            #expect(harness.controller.commandPalettePanel == nil)
            #expect(harness.controller.workspaceSettingsWindow == nil)
            #expect(harness.controller.documentEditedObservation == nil)
            #expect(harness.controller.contentViewController == nil)
            #expect(!settingsWindow.isVisible)
        }
    }

    @Test
    func theSelectedCodeFileIsTheActiveEditorsDocument() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            #expect(harness.controller.getSelectedCodeFile() == nil)

            try harness.openTab("One.swift")

            let codeFile = try #require(harness.controller.getSelectedCodeFile())
            #expect(codeFile.fileURL?.lastPathComponent == "One.swift")
        }
    }

    @Test
    func theMarkdownClipboardReadsTheInjectedPasteboardUnlessOverridden() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            let pasteboard = InMemoryPasteboard()
            harness.controller.markdownPasteboard = pasteboard

            #expect(harness.controller.markdownClipboard() == nil)

            pasteboard.replaceContents(withText: "https://example.com")
            #expect(harness.controller.markdownClipboard() == "https://example.com")

            harness.controller.markdownClipboard = { "override" }
            #expect(harness.controller.markdownClipboard() == "override")
        }
    }
}
