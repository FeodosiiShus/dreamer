import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct RefactorCommandsTests {
    private func makeWorkspace(_ dir: URL) throws -> WorkspaceDocument {
        try "alpha\n".write(to: dir.appending(path: "a.txt"), atomically: true, encoding: .utf8)
        let workspace = try HostedViewFixture.makeWorkspace(in: dir)
        let file = try #require(workspace.workspaceFileManager?.getFile(
            dir.appending(path: "a.txt").path(percentEncoded: false),
            createIfNotFound: true
        ))
        workspace.editorManager?.openTab(item: file)
        return workspace
    }

    @Test
    func commandsBodyBuilds() {
        let commands = RefactorCommands()

        _ = commands.body
    }

    @Test
    func renameSendsItsResponderChainSelector() {
        let recorder = CommandsBSelectorRecorder()
        let menu = RefactorMenu(windowController: nil, sendAction: { recorder.record($0) })

        menu.rename()

        #expect(recorder.selectors == [#selector(DreamderWindowController.renameSymbol(_:))])
        #expect(menu.canRefactor == false)
    }

    @Test
    func navigationExtrasSendTheRecentLocationsSelector() {
        let recorder = CommandsBSelectorRecorder()
        let items = NavigationExtrasMenuItems(windowController: nil, sendAction: { recorder.record($0) })

        items.showRecentLocations()
        items.goToImplementation()

        #expect(recorder.selectors == [#selector(DreamderWindowController.showRecentLocations(_:))])
        #expect(items.canNavigate == false)
    }

    @Test
    func editorIntelligenceActionsAreNoOpsWithoutAWorkspace() async {
        let menu = EditorIntelligenceMenu(windowController: nil)

        await menu.expandSelection()
        menu.shrinkSelection()
        await menu.showParameterInfo()
        await menu.collapseCodeBlock()
        menu.expandCodeBlock()
        await menu.collapseAll()
        menu.expandAll()
        await menu.collapseComments()

        #expect(menu.hasEditor == false)
        #expect(menu.hasLanguageServer == false)
    }

    @Test
    func editorIntelligenceActionsAreNoOpsWhenTheActiveTabHasNoCoordinators() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir)
            defer { workspace.close() }
            let controller = makeCommandsBWindowController(workspace: workspace)
            defer { controller.window?.close() }
            let menu = EditorIntelligenceMenu(windowController: controller)

            await menu.expandSelection()
            menu.shrinkSelection()
            await menu.showParameterInfo()
            await menu.collapseCodeBlock()
            menu.expandCodeBlock()
            await menu.collapseAll()
            menu.expandAll()
            await menu.collapseComments()

            #expect(menu.hasEditor)
            #expect(menu.hasLanguageServer == false)
        }
    }

    @Test
    func menusRenderEveryStateVariant() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir)
            defer { workspace.close() }
            let controller = makeCommandsBWindowController(workspace: workspace)
            defer { controller.window?.close() }

            let detached = HostedViewFixture.host(size: NSSize(width: 600, height: 800)) {
                VStack {
                    RefactorMenu(windowController: nil)
                    EditorIntelligenceMenu(windowController: nil)
                    NavigationExtrasMenuItems(windowController: nil)
                }
            }
            defer { detached.close() }
            try await detached.settle(.milliseconds(100))
            #expect(detached.renders())

            let attached = HostedViewFixture.host(size: NSSize(width: 600, height: 800)) {
                VStack {
                    RefactorMenu(windowController: controller)
                    EditorIntelligenceMenu(windowController: controller)
                    NavigationExtrasMenuItems(windowController: controller)
                }
            }
            defer { attached.close() }
            try await attached.settle(.milliseconds(100))
            #expect(attached.renders())

            #expect(HostedView.pixelsDiffer(detached.snapshot(), attached.snapshot()))
        }
    }

    @Test
    func editorIntelligenceMenuTitlesAndGatingFollowTheActiveTab() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir)
            defer { workspace.close() }
            let controller = makeCommandsBWindowController(workspace: workspace)
            defer { controller.window?.close() }
            let menu = CommandsACoverageSupport.host { EditorIntelligenceMenu(windowController: controller) }
            defer { menu.close() }

            #expect(menu.titles == ["Extend Selection", "Shrink Selection", "Parameter Info", "Code Folding"])
            #expect(menu.enabledStates == [true, true, false, true])

            try menu.click(titled: "Extend Selection")
            try menu.click(titled: "Shrink Selection")
            for _ in 0..<20 {
                await Task.yield()
            }

            let folding = try #require(menu.item(titled: "Code Folding")?.submenu)
            let foldingItems = CommandsACoverageMenu(menu: folding)
            let expectedTitles = ["Collapse", "Expand", "Collapse All", "Expand All", "Collapse Comments"]
            #expect(foldingItems.titles == expectedTitles)
            for title in foldingItems.titles {
                try foldingItems.click(titled: title)
            }
            for _ in 0..<20 {
                await Task.yield()
            }
            #expect(menu.titles.count == 4)
        }
    }

    @Test
    func parameterInfoRequestRunsTheCommandWithoutALanguageServer() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir)
            defer { workspace.close() }
            let controller = makeCommandsBWindowController(workspace: workspace)
            defer { controller.window?.close() }
            let menu = EditorIntelligenceMenu(windowController: controller)
            let host = CommandsACoverageSupport.host { EditorIntelligenceMenu(windowController: controller) }
            defer { host.close() }
            #expect(host.item(titled: "Parameter Info")?.isEnabled == false)

            menu.requestParameterInfo()
            for _ in 0..<20 {
                await Task.yield()
            }

            #expect(menu.hasEditor)
            #expect(menu.hasLanguageServer == false)
        }
    }
}
