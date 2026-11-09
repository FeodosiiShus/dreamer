import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
final class CommandsBSelectorRecorder {
    private(set) var selectors: [Selector] = []

    func record(_ selector: Selector) {
        selectors.append(selector)
    }
}

@MainActor
func makeCommandsBWindowController(workspace: WorkspaceDocument?) -> DreamderWindowController {
    let window = NSWindow()
    window.isReleasedWhenClosed = false
    let controller = DreamderWindowController(window: window, workspace: nil)
    controller.workspace = workspace
    return controller
}

@MainActor
@Suite(.uiGate)
struct NavigateCommandsBCoverageTests {
    private func openTab(_ name: String, in workspace: WorkspaceDocument, dir: URL) throws {
        let file = try #require(workspace.workspaceFileManager?.getFile(
            dir.appending(path: name).path(percentEncoded: false),
            createIfNotFound: true
        ))
        workspace.editorManager?.openTab(item: file)
    }

    private func makeTwoTabWorkspace(_ dir: URL) throws -> (WorkspaceDocument, Editor) {
        try "alpha\n".write(to: dir.appending(path: "a.txt"), atomically: true, encoding: .utf8)
        try "beta\n".write(to: dir.appending(path: "b.txt"), atomically: true, encoding: .utf8)
        let workspace = try HostedViewFixture.makeWorkspace(in: dir)
        try openTab("a.txt", in: workspace, dir: dir)
        try openTab("b.txt", in: workspace, dir: dir)
        let editor = try #require(workspace.editorManager?.activeEditor)
        return (workspace, editor)
    }

    private func selectedName(_ editor: Editor) -> String? {
        editor.selectedTab?.file.url.lastPathComponent
    }

    @Test
    func menuActionsSendTheirResponderChainSelectors() {
        let recorder = CommandsBSelectorRecorder()
        let menu = NavigateMenu(windowController: nil, sendAction: { recorder.record($0) })

        menu.searchEverywhere()
        menu.goToClass()
        menu.goToFile()
        menu.goToSymbol()
        menu.findAction()
        menu.recentFiles()
        menu.showUsages()
        menu.findUsages()
        menu.revealInProjectNavigator()

        #expect(recorder.selectors == [
            #selector(DreamderWindowController.openSearchEverywhere(_:)),
            #selector(DreamderWindowController.openSearchEverywhereClasses(_:)),
            #selector(DreamderWindowController.openSearchEverywhereFiles(_:)),
            #selector(DreamderWindowController.openSearchEverywhereSymbols(_:)),
            #selector(DreamderWindowController.openSearchEverywhereActions(_:)),
            #selector(DreamderWindowController.openRecentFiles(_:)),
            #selector(DreamderWindowController.showUsages(_:)),
            #selector(DreamderWindowController.findUsages(_:)),
            #selector(ProjectNavigatorViewController.revealFile(_:))
        ])
    }

    @Test
    func defaultSenderDispatchesThroughTheResponderChain() {
        MenuResponderChain.send(Selector(("dreamderCommandsBNoSuchAction:")))
        let menu = NavigateMenu(windowController: nil)
        #expect(menu.canNavigate == false)
    }

    @Test
    func editorActionsAreNoOpsWithoutAWorkspace() {
        let controller = makeCommandsBWindowController(workspace: nil)
        defer { controller.window?.close() }
        let menu = NavigateMenu(windowController: controller)

        menu.showPreviousTab()
        menu.showNextTab()
        menu.goBack()
        menu.goForward()
        menu.goToDeclaration()
        menu.goToTypeDeclaration()

        #expect(menu.canNavigate == false)
        #expect(controller.workspace == nil)
    }

    @Test
    func tabActionsCycleThroughTheActiveEditorTabs() throws {
        try withTempDir { dir in
            let (workspace, editor) = try makeTwoTabWorkspace(dir)
            defer { workspace.close() }
            let controller = makeCommandsBWindowController(workspace: workspace)
            defer { controller.window?.close() }
            let menu = NavigateMenu(windowController: controller)
            #expect(selectedName(editor) == "b.txt")

            menu.showPreviousTab()
            #expect(selectedName(editor) == "a.txt")

            menu.showPreviousTab()
            #expect(selectedName(editor) == "b.txt")

            menu.showNextTab()
            #expect(selectedName(editor) == "a.txt")

            menu.showNextTab()
            #expect(selectedName(editor) == "b.txt")
        }
    }

    @Test
    func historyActionsWalkTheRecentLocationsAcrossFiles() async throws {
        try await withTempDir { dir in
            try "alpha\n".write(to: dir.appending(path: "a.txt"), atomically: true, encoding: .utf8)
            try "beta\n".write(to: dir.appending(path: "b.txt"), atomically: true, encoding: .utf8)
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            try openTab("a.txt", in: workspace, dir: dir)
            let editor = try #require(workspace.editorManager?.activeEditor)
            let controller = makeCommandsBWindowController(workspace: workspace)
            defer { controller.window?.close() }
            let menu = NavigateMenu(windowController: controller)
            #expect(EditorLocationHistoryCommands.canGoBack(workspace: workspace) == false)

            try openTab("b.txt", in: workspace, dir: dir)
            try await eventually { EditorLocationHistoryCommands.canGoBack(workspace: workspace) }
            #expect(EditorLocationHistoryCommands.canGoForward(workspace: workspace) == false)

            menu.goBack()
            #expect(selectedName(editor) == "a.txt")
            #expect(EditorLocationHistoryCommands.canGoForward(workspace: workspace))

            menu.goForward()
            #expect(selectedName(editor) == "b.txt")
            #expect(EditorLocationHistoryCommands.canGoForward(workspace: workspace) == false)
        }
    }

    @Test
    func languageNavigationWithoutAServerKeepsTheSelection() async throws {
        try await withTempDir { dir in
            let (workspace, editor) = try makeTwoTabWorkspace(dir)
            defer { workspace.close() }
            let controller = makeCommandsBWindowController(workspace: workspace)
            defer { controller.window?.close() }
            let menu = NavigateMenu(windowController: controller)

            menu.goToDeclaration()
            menu.goToTypeDeclaration()
            try await Task.sleep(for: .milliseconds(100))

            #expect(menu.canNavigate == false)
            #expect(selectedName(editor) == "b.txt")
            #expect(editor.tabs.count == 2)
        }
    }

    @Test
    func menuRendersEveryStateVariant() async throws {
        try await withTempDir { dir in
            let (workspace, _) = try makeTwoTabWorkspace(dir)
            defer { workspace.close() }
            let controller = makeCommandsBWindowController(workspace: workspace)
            defer { controller.window?.close() }

            let detached = HostedViewFixture.host(size: NSSize(width: 600, height: 800)) {
                VStack { NavigateMenu(windowController: nil) }
            }
            defer { detached.close() }
            try await detached.settle(.milliseconds(100))
            #expect(detached.renders())

            let attached = HostedViewFixture.host(size: NSSize(width: 600, height: 800)) {
                VStack { NavigateMenu(windowController: controller) }
            }
            defer { attached.close() }
            try await attached.settle(.milliseconds(100))
            #expect(attached.renders())

            #expect(HostedView.pixelsDiffer(detached.snapshot(), attached.snapshot()))
        }
    }
}
