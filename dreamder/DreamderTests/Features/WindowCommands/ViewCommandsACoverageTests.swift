import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct ViewCommandsACoverageTests {
    @MainActor
    private struct Harness {
        let workspace: WorkspaceDocument
        let controller: DreamderWindowController
        let manager: ToolWindowManager
        let editors: EditorManager

        func close() {
            controller.window?.close()
            workspace.close()
        }
    }

    private func makeHarness(in directory: URL) throws -> Harness {
        try "let one = 1\n".write(to: directory.appending(path: "One.swift"), atomically: true, encoding: .utf8)
        let workspace = WorkspaceDocument()
        try workspace.read(from: directory, ofType: "")
        workspace.makeWindowControllers()
        let controller = try #require(workspace.windowControllers.first as? DreamderWindowController)
        controller.window?.isReleasedWhenClosed = false
        let editors = try #require(workspace.editorManager)
        let file = try #require(workspace.workspaceFileManager?.getFile(
            directory.appending(path: "One.swift").path(percentEncoded: false),
            createIfNotFound: true
        ))
        editors.openTab(item: file)
        return Harness(
            workspace: workspace,
            controller: controller,
            manager: workspace.toolWindowManager,
            editors: editors
        )
    }

    private func withFontSettings(_ body: (Dreamder.Settings) throws -> Void) throws {
        try withTempDir { directory in
            try body(Dreamder.Settings(baseURL: directory))
        }
    }

    @Test
    func editorSplitButtonsDriveTheWindowControllerSplitActions() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            let menu = CommandsACoverageSupport.host {
                ViewCommands.EditorSplitButtons(target: harness.controller)
            }
            defer { menu.close() }

            try menu.click(0)
            #expect(harness.editors.flattenedEditors.count == 2)

            try menu.click(1)
            #expect(harness.editors.flattenedEditors.count == 3)

            let before = harness.editors.activeEditor
            try menu.click(5)
            #expect(harness.editors.activeEditor !== before)
            try menu.click(6)
            #expect(harness.editors.activeEditor === before)

            try menu.click(4)
            try menu.click(2)
            #expect(harness.editors.flattenedEditors.count == 2)

            try menu.click(3)
            #expect(harness.editors.flattenedEditors.count == 1)
        }
    }

    @Test
    func commandPaletteButtonSendsOpenCommandPalette() throws {
        let recorder = CommandsACoverageRecorder()
        let menu = CommandsACoverageSupport.host {
            ViewCommands.CommandPaletteButton(target: recorder)
        }
        defer { menu.close() }

        try menu.click(0)

        #expect(recorder.received == ["openCommandPalette(_:)"])
    }

    @Test
    func fontSizeButtonsIncreaseDecreaseAndResetBothFonts() throws {
        try withFontSettings { store in
            let menu = CommandsACoverageSupport.host {
                ViewCommands.FontSizeButtons().environment(\.settingsStore, store)
            }
            defer { menu.close() }
            store.preferences.textEditing.font.size = 13
            store.preferences.terminal.font.size = 12

            try menu.click(titled: "Increase")
            #expect(store.preferences.textEditing.font.size == 14)
            #expect(store.preferences.terminal.font.size == 13)

            try menu.click(titled: "Decrease")
            #expect(store.preferences.textEditing.font.size == 13)
            #expect(store.preferences.terminal.font.size == 12)

            try menu.click(titled: "Reset")
            #expect(store.preferences.textEditing.font.size == 12)
            #expect(store.preferences.terminal.font.size == 12)
        }
    }

    @Test
    func fontSizeButtonsStopAtTheUpperLimit() throws {
        try withFontSettings { store in
            let menu = CommandsACoverageSupport.host {
                ViewCommands.FontSizeButtons().environment(\.settingsStore, store)
            }
            defer { menu.close() }
            store.preferences.textEditing.font.size = 288
            store.preferences.terminal.font.size = 287

            try menu.click(0)

            #expect(store.preferences.textEditing.font.size == 288)
            #expect(store.preferences.terminal.font.size == 288)

            try menu.click(0)

            #expect(store.preferences.terminal.font.size == 288)
        }
    }

    @Test
    func fontSizeButtonsStopAtTheLowerLimit() throws {
        try withFontSettings { store in
            let menu = CommandsACoverageSupport.host {
                ViewCommands.FontSizeButtons().environment(\.settingsStore, store)
            }
            defer { menu.close() }
            store.preferences.textEditing.font.size = 1
            store.preferences.terminal.font.size = 2

            try menu.click(1)

            #expect(store.preferences.textEditing.font.size == 1)
            #expect(store.preferences.terminal.font.size == 1)

            try menu.click(1)

            #expect(store.preferences.terminal.font.size == 1)
        }
    }

    @Test
    func toolWindowButtonsToggleEachToolWindow() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            harness.manager.hideAll()
            let menu = CommandsACoverageSupport.host {
                ViewCommands.ToolWindowButtons(windowController: harness.controller)
            }
            defer { menu.close() }

            try menu.click(3)
            #expect(harness.manager.isVisible(.find))

            let toggles: [(index: Int, id: ToolWindowID)] = [
                (0, .project),
                (1, .commit),
                (2, .structure),
                (4, .run),
                (5, .problems),
                (6, .git),
                (7, .languageServices),
                (8, .terminal)
            ]
            for toggle in toggles {
                try menu.click(toggle.index)
                #expect(harness.manager.isVisible(toggle.id))
            }
        }
    }

    @Test
    func hideAllAndMaximizeBottomButtonsDriveTheToolWindowManager() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            harness.manager.hideAll()
            harness.manager.show(.project)
            harness.manager.show(.terminal)
            let menu = CommandsACoverageSupport.host {
                ViewCommands.ToolWindowButtons(windowController: harness.controller)
            }
            defer { menu.close() }

            try menu.click(9)
            #expect(harness.manager.active(.left) == nil)
            #expect(harness.manager.active(.bottom) == nil)

            try menu.click(10)
            #expect(harness.manager.isVisible(.terminal))
            #expect(harness.manager.bottomMaximized)

            try menu.click(10)
            #expect(harness.manager.bottomMaximized == false)
        }
    }

    @Test
    func toolWindowButtonsDoNothingWithoutAWindowController() throws {
        let menu = CommandsACoverageSupport.host {
            ViewCommands.ToolWindowButtons(windowController: nil)
        }
        defer { menu.close() }

        for index in 0..<11 {
            try menu.click(index)
        }

        #expect(menu.items.count == 11)
    }

    @Test
    func toolbarButtonTogglesTheToolbar() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            let before = harness.controller.toolbarCollapsed
            let menu = CommandsACoverageSupport.host {
                ViewCommands.HideButtons(windowController: harness.controller)
            }
            defer { menu.close() }

            try menu.click(0)

            #expect(harness.controller.toolbarCollapsed == !before)
        }
    }

    @Test
    func interfaceButtonHidesTheToolWindows() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            harness.manager.hideAll()
            harness.manager.show(.project)
            harness.manager.show(.terminal)
            let menu = CommandsACoverageSupport.host {
                ViewCommands.HideButtons(windowController: harness.controller)
            }
            defer { menu.close() }

            try menu.click(1)

            #expect(harness.manager.active(.left) == nil)
            #expect(harness.manager.active(.bottom) == nil)
        }
    }

    @Test
    func hideButtonsAreDisabledWithoutAWindowController() {
        let menu = CommandsACoverageSupport.host {
            ViewCommands.HideButtons(windowController: nil)
        }
        defer { menu.close() }

        #expect(menu.titles == ["Show Toolbar", "Hide Interface"])
        #expect(menu.enabledStates == [false, false])
    }

    @Test
    func hideButtonsOfferToShowTheInterfaceWhileEverythingIsCollapsed() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            harness.manager.hideAll()
            harness.controller.toolbarCollapsed = true
            let menu = CommandsACoverageSupport.host {
                ViewCommands.HideButtons(windowController: harness.controller)
            }
            defer { menu.close() }

            #expect(menu.titles == ["Show Toolbar", "Show Interface"])
            #expect(menu.enabledStates == [true, true])
        }
    }

    @Test
    func trackedWrappersRenderTheirItems() throws {
        let hide = CommandsACoverageSupport.host {
            ViewCommands.HideCommands()
        }
        let tools = CommandsACoverageSupport.host {
            ViewCommands.ToolWindowMenu()
        }
        defer {
            hide.close()
            tools.close()
        }

        #expect(hide.items.count == 2)
        #expect(tools.titles == ["Tool Windows"])
        let parent = try #require(tools.items.first)
        let nested = parent.submenu?.items.filter { !$0.isSeparatorItem } ?? []
        #expect(!parent.isEnabled || nested.allSatisfy { !$0.isEnabled })
    }

    @Test
    func commandBodyBuilds() {
        _ = ViewCommands().body
    }
}
