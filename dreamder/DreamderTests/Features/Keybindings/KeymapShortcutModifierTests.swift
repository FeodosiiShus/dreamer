import Foundation
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct KeymapShortcutModifierTests {
    private func makeKeymap() throws -> (keymap: Keymap, defaults: UserDefaults, suiteName: String) {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        return (Keymap(defaults: defaults), defaults, suiteName)
    }

    @Test
    func theResolvedShortcutIsTheRegistryShortcutWhenEnabled() throws {
        let (keymap, defaults, suiteName) = try makeKeymap()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }

        #expect(
            KeymapShortcutModifier.shortcut(for: .goToDeclaration, at: 0, isEnabled: true, in: keymap)
                == KeyboardShortcut("b", modifiers: .command)
        )
        #expect(KeymapShortcutModifier.shortcut(for: .goToDeclaration, at: 0, isEnabled: false, in: keymap) == nil)
        #expect(KeymapShortcutModifier.shortcut(for: .quickDocumentation, at: 1, isEnabled: true, in: keymap) != nil)
        #expect(KeymapShortcutModifier.shortcut(for: .goToClass, at: 0, isEnabled: true, in: keymap) == nil)
    }

    @Test
    func changingTheKeymapChangesTheResolvedShortcutAndClearingRemovesIt() throws {
        let (keymap, defaults, suiteName) = try makeKeymap()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }

        keymap.replaceShortcuts(of: .save, with: .stroke("s", [.option, .command]))
        #expect(
            KeymapShortcutModifier.shortcut(for: .save, at: 0, isEnabled: true, in: keymap)
                == KeyboardShortcut("s", modifiers: [.option, .command])
        )

        keymap.removeAllShortcuts(from: .save)
        #expect(KeymapShortcutModifier.shortcut(for: .save, at: 0, isEnabled: true, in: keymap) == nil)
    }

    @Test
    func theModifierRendersWithTheInjectedKeymapTheSharedOneAndWhenDisabled() async throws {
        let (keymap, defaults, suiteName) = try makeKeymap()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }

        let injected = HostedViewFixture.host(size: NSSize(width: 200, height: 60)) {
            Button("Save") {}
                .keymapShortcut(.save)
                .keymapShortcut(.quickDocumentation, at: 1)
                .environment(keymap)
        }
        defer { injected.close() }
        let shared = HostedViewFixture.host(size: NSSize(width: 200, height: 60)) {
            Button("Find") {}
                .keymapShortcut(.find)
        }
        defer { shared.close() }
        let disabled = HostedViewFixture.host(size: NSSize(width: 200, height: 60)) {
            Button("Find") {}
                .keymapShortcut(.find, when: false)
                .environment(keymap)
        }
        defer { disabled.close() }

        try await injected.settle(.milliseconds(40))
        keymap.replaceShortcuts(of: .save, with: .stroke("s", [.option, .command]))
        try await injected.settle(.milliseconds(40))
        try await shared.settle(.milliseconds(40))
        try await disabled.settle(.milliseconds(40))

        #expect(injected.renders())
        #expect(shared.renders())
        #expect(disabled.renders())
    }

    @Test
    func windowCommandMenusRenderWithAnInjectedKeymap() async throws {
        let (keymap, defaults, suiteName) = try makeKeymap()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        keymap.removeAllShortcuts(from: .find)
        keymap.replaceShortcuts(of: .toolWindowProject, with: .stroke("p", [.control, .command]))
        let views: [AnyView] = [
            AnyView(FindCommands.FindButtons(responder: nil)),
            AnyView(FindInFilesMenu(windowController: nil)),
            AnyView(FileCommands.DocumentButtons()),
            AnyView(FileCommands.CloseButtons()),
            AnyView(FileCommands.WorkspaceButtons(isWorkspaceSettingsEnabled: false)),
            AnyView(ViewCommands.ToolWindowButtons(windowController: nil)),
            AnyView(ViewCommands.EditorSplitButtons()),
            AnyView(ViewCommands.CommandPaletteButton()),
            AnyView(ViewCommands.HideButtons(windowController: nil)),
            AnyView(EditorCommands.MoveLinesButtons(currentTab: { nil })),
            AnyView(EditorCommands.QuickDocumentationButtons(isEnabled: true)),
            AnyView(SourceControlMenu(windowController: nil, hasUnmergedFiles: false)),
            AnyView(TasksCommands.RunButtons(taskManager: nil, toolWindowManager: nil)),
            AnyView(TasksCommands.ManageTasksButton(isEnabled: false)),
            AnyView(AppearanceCommands.BackgroundImageButtons())
        ]

        for view in views {
            let hosted = HostedViewFixture.host(size: NSSize(width: 260, height: 400)) {
                view.environment(keymap)
            }
            defer { hosted.close() }
            try await hosted.settle(.milliseconds(30))
            #expect(hosted.renders())
        }
    }

    @Test
    func windowCommandSourcesTakeEveryShortcutFromTheRegistry() throws {
        let directory = IntelliJTestData.url("dreamder/Dreamder/Features/WindowCommands")
        let enumerator = try #require(FileManager.default.enumerator(atPath: directory.path(percentEncoded: false)))
        let sources = try enumerator.compactMap { $0 as? String }
            .filter { $0.hasSuffix(".swift") }
            .map { try String(contentsOf: directory.appending(path: $0), encoding: .utf8) }
            .joined(separator: "\n")

        #expect(!sources.contains(".keyboardShortcut("))
        for command in Self.menuCommands {
            let closed = sources.contains(".keymapShortcut(.\(command))")
            let withIndex = sources.contains(".keymapShortcut(.\(command),")
            #expect(closed || withIndex, "\(command)")
        }
    }

    private static let menuCommands: [KeymapCommand] = [
        .about, .settings, .newDocument, .openDocument, .closeTab, .closeEditor, .closeWindow, .closeWorkspace,
        .closeTerminal, .workspaceSettings, .save,
        .toolWindowProject, .toolWindowCommit, .toolWindowStructure, .toolWindowFind, .toolWindowRun,
        .toolWindowProblems, .toolWindowGit, .toolWindowLanguageServices, .toolWindowTerminal,
        .hideAllToolWindows, .maximizeBottomToolWindow,
        .splitRight, .splitDown, .unsplit, .unsplitAll, .changeSplitterOrientation, .gotoNextSplitter,
        .gotoPreviousSplitter, .commandPalette, .increaseFontSize, .decreaseFontSize, .resetFontSize,
        .toggleToolbar, .toggleInterface, .dimEditorsWithoutFocus, .chooseBackgroundImage, .clearBackgroundImage,
        .toggleInlayHints,
        .find, .findAndReplace, .findNext, .findPrevious, .useSelectionForFind, .jumpToSelection,
        .findInFiles, .replaceInFiles,
        .searchEverywhere, .goToClass, .goToFile, .goToSymbol, .findAction, .recentFiles, .goToDeclaration,
        .goToTypeDeclaration, .showUsages, .findUsages, .revealInProjectNavigator, .previousTab, .nextTab,
        .goBack, .goForward,
        .moveLineUp, .moveLineDown, .quickDocumentation,
        .runTask, .stopTask, .showTaskOutput, .manageTasks,
        .gitBranches, .gitResolveConflicts, .gitCommit, .gitPush, .gitUpdateProject, .gitFetch, .gitNewBranch,
        .gitPull, .gitFetchChanges, .gitStageAll, .gitUnstageAll, .gitStash, .gitDiscardAll, .gitAddRemote,
        .windowWelcome, .windowAbout
    ]
}
