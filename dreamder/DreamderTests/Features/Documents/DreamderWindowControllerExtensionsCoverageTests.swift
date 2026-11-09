import AppKit
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct DreamderWindowControllerExtensionsCoverageTests {
    @MainActor
    private struct Harness {
        let directory: URL
        let workspace: WorkspaceDocument
        let controller: DreamderWindowController
        let window: NSWindow

        func openTab(_ name: String) throws {
            let path = directory.appending(path: name).path(percentEncoded: false)
            let file = try #require(workspace.workspaceFileManager?.getFile(path, createIfNotFound: true))
            workspace.editorManager?.openTab(item: file)
        }

        func close() {
            for child in window.childWindows ?? [] {
                child.close()
            }
            window.close()
            workspace.close()
        }
    }

    private func makeHarness(in directory: URL) throws -> Harness {
        for name in ["One.swift", "Two.swift"] {
            try "let value = 1\n".write(to: directory.appending(path: name), atomically: true, encoding: .utf8)
        }
        let workspace = WorkspaceDocument()
        try workspace.read(from: directory, ofType: "")
        workspace.makeWindowControllers()
        let controller = try #require(workspace.windowControllers.first as? DreamderWindowController)
        let window = try #require(controller.window)
        window.isReleasedWhenClosed = false
        window.orderFront(nil)
        return Harness(directory: directory, workspace: workspace, controller: controller, window: window)
    }

    @Test
    func theControllerRegistersItsCommandsForThePalette() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            let manager = CommandManager.shared
            let titles = Set(manager.commands.map(\.title))
            let manifest = [
                "Quick Open",
                "Toggle Project Tool Window",
                "Toggle Terminal Tool Window",
                "Hide All Tool Windows",
                "Show Terminal Tool Window"
            ]

            #expect(titles.isSuperset(of: manifest))

            let tools = harness.workspace.toolWindowManager
            tools.hideAll()
            manager.executeCommand("toggle_left_sidebar")
            #expect(tools.isVisible(.project))

            manager.executeCommand("toggle_terminal_tool_window")
            #expect(tools.isVisible(.terminal))

            manager.executeCommand("hide_all_tool_windows")
            #expect(tools.visibleWindows.isEmpty)

            manager.executeCommand("show_terminal_tool_window")
            #expect(tools.isVisible(.terminal))

            manager.executeCommand("quick_open")
            #expect(harness.controller.quickOpenPanel != nil)
        }
    }

    @Test
    func editingAnOpenDocumentMarksTheWindowEditedUntilItIsSaved() async throws {
        try await withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            try harness.openTab("One.swift")
            let codeFile = try #require(harness.controller.getSelectedCodeFile())
            codeFile.autosavingInPlace = { false }
            #expect(!harness.window.isDocumentEdited)

            codeFile.updateChangeCount(.changeDone)
            try await eventually(timeout: .seconds(30)) { harness.window.isDocumentEdited }

            let token = codeFile.changeCountToken(for: .saveOperation)
            codeFile.updateChangeCount(withToken: token, for: .saveOperation)
            try await eventually(timeout: .seconds(30)) { !harness.window.isDocumentEdited }
        }
    }

    @Test
    func theWindowStaysEditedWhileAnotherOpenDocumentIsStillEdited() async throws {
        try await withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            try harness.openTab("One.swift")
            let first = try #require(harness.controller.getSelectedCodeFile())
            try harness.openTab("Two.swift")
            let second = try #require(harness.controller.getSelectedCodeFile())
            let editorManager = try #require(harness.workspace.editorManager)
            first.autosavingInPlace = { false }
            second.autosavingInPlace = { false }
            #expect(!DreamderWindowController.hasEditedDocuments(in: editorManager))

            first.updateChangeCount(.changeDone)
            second.updateChangeCount(.changeDone)
            try await eventually(timeout: .seconds(30)) { harness.window.isDocumentEdited }

            second.updateChangeCount(.changeCleared)

            #expect(DreamderWindowController.hasEditedDocuments(in: editorManager))
            first.updateChangeCount(.changeCleared)
            #expect(!DreamderWindowController.hasEditedDocuments(in: editorManager))
            try await eventually(timeout: .seconds(30)) { !harness.window.isDocumentEdited }
        }
    }

    @Test
    func closingAnEditedTabClearsTheWindowEditedState() async throws {
        try await withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            try harness.openTab("One.swift")
            let codeFile = try #require(harness.controller.getSelectedCodeFile())
            codeFile.autosavingInPlace = { false }
            codeFile.closeConfirmation = { _ in true }
            codeFile.updateChangeCount(.changeDone)
            try await eventually(timeout: .seconds(30)) { harness.window.isDocumentEdited }

            harness.workspace.editorManager?.activeEditor.closeSelectedTab()

            try await eventually(timeout: .seconds(30)) { !harness.window.isDocumentEdited }
        }
    }

    @Test
    func workspaceSettingsOpenAsASheetAndCanBeDismissed() async throws {
        try await withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }

            harness.controller.openWorkspaceSettings(harness.controller)
            let sheet = try #require(harness.controller.workspaceSettingsWindow)

            #expect(harness.window.attachedSheet === sheet)
            #expect(sheet.accessibilityTitle() == "Workspace Settings")
            #expect(sheet.titlebarAppearsTransparent)

            harness.controller.dismissWorkspaceSettings()

            try await eventually(timeout: .seconds(30)) { harness.window.attachedSheet == nil }
        }
    }

    @Test
    func theSettingsWindowIsNotReleasedWhenClosedAndASecondOpeningCreatesAFreshSheet() async throws {
        try await withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }

            harness.controller.openWorkspaceSettings(harness.controller)
            let first = try #require(harness.controller.workspaceSettingsWindow)
            #expect(!first.isReleasedWhenClosed)

            harness.controller.dismissWorkspaceSettings()
            try await eventually(timeout: .seconds(30)) { harness.window.attachedSheet == nil }
            first.close()
            #expect(!first.isVisible)

            harness.controller.openWorkspaceSettings(harness.controller)
            let second = try #require(harness.controller.workspaceSettingsWindow)

            #expect(second !== first)
            #expect(!second.isReleasedWhenClosed)
            #expect(harness.window.attachedSheet === second)
        }
    }

    @Test
    func openingWorkspaceSettingsAgainReusesTheVisibleWindow() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            let existing = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            existing.isReleasedWhenClosed = false
            existing.orderFront(nil)
            defer {
                harness.controller.workspaceSettingsWindow = nil
                existing.close()
            }
            harness.controller.workspaceSettingsWindow = existing

            harness.controller.openWorkspaceSettings(harness.controller)

            #expect(harness.controller.workspaceSettingsWindow === existing)
            #expect(harness.window.attachedSheet == nil)
        }
    }

    @Test
    func workspaceSettingsNeedAWorkspaceAndAWindow() {
        let window = NSWindow()
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let controller = DreamderWindowController(window: window, workspace: nil)

        controller.openWorkspaceSettings(controller)
        controller.dismissWorkspaceSettings()

        #expect(controller.workspaceSettingsWindow == nil)
        #expect(window.attachedSheet == nil)
    }
}
