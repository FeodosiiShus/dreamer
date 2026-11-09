import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct IslandsWorkspaceHandlersTests {
    @Test
    func theUtilityAreaShowsTheRunWindowOnlyWhileATaskShowsOutput() {
        #expect(IslandsWorkspaceView.utilityWindow(showingOutput: true) == .run)
        #expect(IslandsWorkspaceView.utilityWindow(showingOutput: false) == .terminal)
    }

    @Test
    func dropHandlerAcceptsProvidersAndNoProviders() throws {
        try withTempDir { directory in
            let workspace = try HostedViewFixture.makeWorkspace(in: directory)
            defer { workspace.close() }
            let editorManager = try #require(workspace.editorManager)
            let handler = IslandsWorkspaceView.dropHandler(editorManager: editorManager)

            #expect(handler([]))
            #expect(handler([NSItemProvider()]))
        }
    }

    @Test
    func branchSyncClearsTheCurrentBranchWhenSourceControlIsSwitchedOff() async throws {
        try await withTempDir { directory in
            let workspace = try HostedViewFixture.makeWorkspace(in: directory)
            defer { workspace.close() }
            let editorManager = try #require(workspace.editorManager)
            let manager = SourceControlManager(workspaceURL: directory, editorManager: editorManager)
            workspace.sourceControlManager = manager
            manager.currentBranch = GitBranch(name: "main", longName: "refs/heads/main", upstream: nil, ahead: 0, behind: 0)

            IslandsWorkspaceView.branchSync(in: workspace)(true, false)

            try await eventually { manager.currentBranch == nil }
        }
    }

    @Test
    func colorSchemeAdoptionForwardsTheNewSchemeAndTheMatchSetting() throws {
        try withTempDir { directory in
            let settings = Settings(baseURL: directory)
            let model = ThemeModel(
                baseURL: directory,
                bundledThemesURL: ThemeModel.defaultBundledThemesURL,
                preferencesStore: settings
            )

            model.colorSchemeAdoption(matchAppearance: false)(.light, .dark)
            #expect(model.colorScheme == .dark)

            let dark = try #require(model.selectedDarkTheme)
            model.colorSchemeAdoption(matchAppearance: true)(.dark, .dark)
            #expect(model.selectedTheme == dark)
        }
    }

    @Test
    func toolWindowDragHandlersResizeTheirWindows() {
        let manager = ToolWindowManager()

        manager.leftResizeDrag(availableWidth: 1000)(40)
        #expect(manager.leftWidth == 320)

        manager.bottomResizeDrag(availableHeight: 800)(40)
        #expect(manager.bottomHeight == 260)

        manager.setSplit(.structure, true)
        manager.show(.structure)
        manager.splitDividerDrag(on: .left, total: 600)(100)
        #expect(manager.mainProportion(on: .left) > ToolWindowSplitState.defaultSideWeight)
    }

    @Test
    func theDisplayedLayoutIsTheWholeLayoutUnlessTheActiveEditorIsFocused() {
        let manager = EditorManager()

        #expect(manager.displayedLayout == manager.editorLayout)

        manager.isFocusingActiveEditor = true
        #expect(manager.displayedLayout == manager.activeEditor.getEditorLayout() ?? manager.editorLayout)

        manager.activeEditor = Editor()
        #expect(manager.activeEditor.getEditorLayout() == nil)
        #expect(manager.displayedLayout == manager.editorLayout)
    }

    @Test
    func stripeButtonsTrackHoverAndMoveWindowsBetweenGroupsThroughTheirMenu() throws {
        ToolWindowStripeButton(id: .project).setHovering(true)
        ToolWindowStripeButton(id: .project).setHovering(false)

        let manager = ToolWindowManager()
        let menu = CommandsACoverageSupport.host {
            ToolWindowSplitMenuItem(id: .structure).environment(manager)
        }
        defer { menu.close() }

        try menu.click(0)
        #expect(manager.isSplit(.structure))

        try menu.click(0)
        #expect(!manager.isSplit(.structure))
    }

    @Test
    func resizeHandleForwardsHoverDragAndEnd() {
        var deltas: [CGFloat] = []
        var ends = 0
        let handle = IslandResizeHandle(
            orientation: .vertical,
            onDrag: { deltas.append($0) },
            onDragEnded: { ends += 1 }
        )

        handle.hover(.ended)
        handle.hover(.active(CGPoint(x: 1, y: 1)))
        handle.dragChanged(CGSize(width: 12, height: 3))
        handle.dragEnded()

        #expect(deltas == [12])
        #expect(ends == 1)
    }

    @Test
    func backgroundImageLayerRendersAnImage() async throws {
        let image = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { rect in
            NSColor.systemTeal.setFill()
            rect.fill()
            return true
        }
        let hosted = HostedViewFixture.host(size: NSSize(width: 60, height: 60)) {
            BackgroundImageLayer(image: image)
        }
        defer { hosted.close() }
        try await hosted.settle(.milliseconds(50))

        #expect(hosted.renders())
    }
}
