import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct FindInFilesCommandsTests {
    @Test
    func commandsBodyBuilds() {
        let commands = FindInFilesCommands()

        _ = commands.body
    }

    @Test
    func keymapEntriesDescribeFindAndReplaceInFiles() {
        #expect(KeymapCommand.findInFiles.id == "find.findInFiles")
        #expect(KeymapCommand.replaceInFiles.id == "find.replaceInFiles")
        #expect(KeymapCommand.findInFiles.title == "Find in Files...")
        #expect(KeymapCommand.replaceInFiles.title == "Replace in Files...")
        #expect(KeymapCommand.findInFiles.group == .find)
        #expect(KeymapCommand.replaceInFiles.group == .find)
        #expect(KeymapCommand.findInFiles.defaultShortcuts.map(\.text) == ["shift command f"])
        #expect(KeymapCommand.replaceInFiles.defaultShortcuts.map(\.text) == ["shift command r"])
        #expect(KeymapCommand(rawValue: "find.findInFiles") == .findInFiles)
        #expect(KeymapCommand(rawValue: "find.replaceInFiles") == .replaceInFiles)
    }

    @Test
    func defaultShortcutsAreUniqueToTheFindInFilesCommands() {
        for command in [KeymapCommand.findInFiles, .replaceInFiles] {
            for shortcut in command.defaultShortcuts {
                let owners = KeymapCommand.allCases.filter { $0.defaultShortcuts.contains(shortcut) }
                #expect(owners == [command], "\(command.id)")
            }
        }
    }

    @Test
    func showingFindRevealsTheToolWindowAndRequestsFocus() async throws {
        try withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let state = try #require(workspace.searchState)
            workspace.toolWindowManager.hide(.find)
            #expect(!workspace.toolWindowManager.isVisible(.find))
            #expect(!state.shouldFocusSearchField)

            FindInFilesAction.show(replace: false, in: workspace)

            #expect(workspace.toolWindowManager.isVisible(.find))
            #expect(!state.selectedMode.isReplaceMode)
            #expect(state.shouldFocusSearchField)
        }
    }

    @Test
    func showingReplaceSwitchesTheModeAndShowingFindSwitchesBack() async throws {
        try withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let state = try #require(workspace.searchState)

            FindInFilesAction.show(replace: true, in: workspace)
            #expect(workspace.toolWindowManager.isVisible(.find))
            #expect(state.selectedMode.isReplaceMode)
            #expect(state.selectedMode.first == .Replace)
            #expect(state.shouldFocusSearchField)

            state.shouldFocusSearchField = false
            FindInFilesAction.show(replace: false, in: workspace)
            #expect(!state.selectedMode.isReplaceMode)
            #expect(state.selectedMode.first == .Find)
            #expect(state.shouldFocusSearchField)
        }
    }

    @Test
    func showingWithoutAWorkspaceOrSearchStateIsHandled() async throws {
        FindInFilesAction.show(replace: true, in: nil)

        try withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            workspace.searchState = nil

            FindInFilesAction.show(replace: true, in: workspace)

            #expect(workspace.toolWindowManager.isVisible(.find))
            #expect(workspace.searchState == nil)
        }
    }

    @Test
    func menuActionsRouteToTheWindowControllersWorkspace() async throws {
        try withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let state = try #require(workspace.searchState)
            let controller = makeCommandsBWindowController(workspace: workspace)
            defer { controller.window?.close() }
            let menu = FindInFilesMenu(windowController: controller)
            #expect(menu.hasWorkspace)

            menu.replaceInFiles()
            #expect(state.selectedMode.isReplaceMode)
            #expect(workspace.toolWindowManager.isVisible(.find))

            menu.findInFiles()
            #expect(!state.selectedMode.isReplaceMode)
        }
    }

    @Test
    func menuActionsWithoutAWorkspaceDoNothing() async throws {
        try withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let controller = makeCommandsBWindowController(workspace: nil)
            defer { controller.window?.close() }
            let menu = FindInFilesMenu(windowController: controller)
            let detached = FindInFilesMenu(windowController: nil)

            workspace.toolWindowManager.hide(.find)
            menu.findInFiles()
            menu.replaceInFiles()
            detached.findInFiles()
            detached.replaceInFiles()

            #expect(!menu.hasWorkspace)
            #expect(!detached.hasWorkspace)
            #expect(!workspace.toolWindowManager.isVisible(.find))
        }
    }

    @Test
    func renderedItemsAreDisabledWithoutAWorkspace() {
        let menu = CommandsACoverageSupport.host {
            FindInFilesMenu(windowController: nil)
        }
        defer { menu.close() }

        #expect(menu.items.count == 2)
        #expect(menu.enabledStates == [false, false])
    }

    @Test
    func renderedItemsShowTheFindToolWindowInTheMatchingMode() async throws {
        try withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let state = try #require(workspace.searchState)
            let controller = makeCommandsBWindowController(workspace: workspace)
            defer { controller.window?.close() }
            let menu = CommandsACoverageSupport.host {
                FindInFilesMenu(windowController: controller)
            }
            defer { menu.close() }

            #expect(menu.enabledStates == [true, true])

            try menu.click(1)
            #expect(workspace.toolWindowManager.isVisible(.find))
            #expect(state.selectedMode.isReplaceMode)

            try menu.click(0)
            #expect(!state.selectedMode.isReplaceMode)
            #expect(state.shouldFocusSearchField)
        }
    }
}
