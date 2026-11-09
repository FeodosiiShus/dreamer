import AppKit
import SwiftUI
import Testing
@testable import Dreamder

extension DreamderWindowControllerCoverageTests {
    @Test
    func closingTheCurrentTabWithoutAnEditorManagerClosesTheWindow() async throws {
        let workspace = WorkspaceDocument()
        workspace.editorManager = nil
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let controller = DreamderWindowController(window: window, workspace: workspace)
        defer { window.close() }
        window.orderFront(nil)

        controller.closeCurrentTab(controller)

        try await eventually(timeout: .seconds(30)) { controller.workspace == nil }
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
}
