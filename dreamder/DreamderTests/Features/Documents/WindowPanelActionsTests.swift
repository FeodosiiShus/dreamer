import AppKit
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized)
struct WindowPanelActionsTests {
    @MainActor
    private struct Harness {
        let workspace: WorkspaceDocument
        let controller: DreamderWindowController
        let window: NSWindow
        let manager: ToolWindowManager

        func close() {
            for child in window.childWindows ?? [] {
                child.close()
            }
            window.close()
            workspace.close()
        }

        func show(_ ids: ToolWindowID...) {
            manager.hideAll()
            for id in ids {
                manager.show(id)
            }
        }
    }

    private func makeHarness(in directory: URL) throws -> Harness {
        let workspace = WorkspaceDocument()
        try workspace.read(from: directory, ofType: "")
        workspace.makeWindowControllers()
        let controller = try #require(workspace.windowControllers.first as? DreamderWindowController)
        let window = try #require(controller.window)
        window.isReleasedWhenClosed = false
        window.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: false)
        return Harness(
            workspace: workspace,
            controller: controller,
            window: window,
            manager: workspace.toolWindowManager
        )
    }

    private func makeWorkspaceLessController() -> DreamderWindowController {
        let window = NSWindow()
        window.isReleasedWhenClosed = false
        return DreamderWindowController(window: window, workspace: nil)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        await waitForExpectation(condition) {
            Issue.record("Condition not reached in time")
        }
    }

    @Test
    func toggleFirstPanelShowsProjectAndTogglesItAway() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            harness.manager.hideAll()

            harness.controller.toggleFirstPanel()
            let shown = harness.manager.isVisible(.project)

            harness.controller.toggleFirstPanel()
            let hidden = !harness.manager.isVisible(.project)

            #expect(shown)
            #expect(hidden)
        }
    }

    @Test
    func toggleFirstPanelReplacesAnotherLeftToolWindowWithProject() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            harness.show(.structure)

            harness.controller.toggleFirstPanel()

            #expect(harness.manager.active(.left) == .project)
            #expect(!harness.manager.isVisible(.structure))
        }
    }

    @Test
    func objcToggleFirstPanelTogglesProject() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            harness.show(.project)

            harness.controller.objcToggleFirstPanel()

            #expect(harness.manager.active(.left) == nil)
        }
    }

    @Test
    func toggleToolWindowShowsAndHidesThatWindowOnly() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            harness.show(.project)

            harness.controller.toggleToolWindow(.find)
            let findShown = harness.manager.isVisible(.find)
            let projectKept = harness.manager.isVisible(.project)

            harness.controller.toggleToolWindow(.find)
            let findHidden = !harness.manager.isVisible(.find)

            #expect(findShown)
            #expect(projectKept)
            #expect(findHidden)
        }
    }

    @Test
    func toggleToolWindowOfSameAnchorReplacesVisibleOne() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            harness.show(.terminal)

            harness.controller.toggleToolWindow(.problems)

            #expect(harness.manager.active(.bottom) == .problems)
            #expect(!harness.manager.isVisible(.terminal))
        }
    }

    @Test
    func toggleLastPanelHidesAnyActiveBottomToolWindow() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            harness.show(.problems)

            harness.controller.toggleLastPanel()

            #expect(harness.manager.active(.bottom) == nil)
        }
    }

    @Test
    func toggleLastPanelShowsTerminalWhenBottomIsEmpty() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            harness.show(.project)

            harness.controller.toggleLastPanel()

            #expect(harness.manager.active(.bottom) == .terminal)
            #expect(harness.manager.isVisible(.project))
        }
    }

    @Test
    func toggleLastPanelHidesMainAndSplitSlotsAndClearsMaximize() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            harness.manager.setSplit(.git, true)
            harness.show(.terminal, .git)
            harness.manager.bottomMaximized = true

            harness.controller.toggleLastPanel()

            let mainEmpty = harness.manager.visible(on: .bottom, side: .main) == nil
            let splitEmpty = harness.manager.visible(on: .bottom, side: .split) == nil
            #expect(mainEmpty)
            #expect(splitEmpty)
            #expect(!harness.manager.bottomMaximized)
        }
    }

    @Test
    func objcToggleLastPanelTogglesBottomAnchor() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            harness.manager.hideAll()

            harness.controller.objcToggleLastPanel()
            let shown = harness.manager.active(.bottom) == .terminal

            harness.controller.objcToggleLastPanel()
            let hidden = harness.manager.active(.bottom) == nil

            #expect(shown)
            #expect(hidden)
        }
    }

    @Test
    func toggleLeftPanelHidesAnyActiveLeftToolWindow() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            harness.show(.structure)

            harness.controller.toggleLeftPanel()

            #expect(harness.manager.active(.left) == nil)
        }
    }

    @Test
    func toggleLeftPanelShowsProjectWhenLeftIsEmptyAndLeavesBottomAlone() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            harness.show(.problems)

            harness.controller.toggleLeftPanel()

            #expect(harness.manager.active(.left) == .project)
            #expect(harness.manager.active(.bottom) == .problems)
        }
    }

    @Test
    func toggleLeftPanelHidesWhenOnlySplitSlotIsOccupied() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            harness.manager.setSplit(.commit, true)
            harness.show(.commit)

            harness.controller.toggleLeftPanel()

            let mainEmpty = harness.manager.visible(on: .left, side: .main) == nil
            let splitEmpty = harness.manager.visible(on: .left, side: .split) == nil
            #expect(mainEmpty)
            #expect(splitEmpty)
        }
    }

    @Test
    func hideAllToolWindowsClearsBothAnchorsAndMaximize() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            harness.show(.project, .terminal)
            harness.manager.bottomMaximized = true

            harness.controller.hideAllToolWindows()

            #expect(harness.manager.active(.left) == nil)
            #expect(harness.manager.active(.bottom) == nil)
            #expect(harness.manager.visibleWindows.isEmpty)
            #expect(!harness.manager.bottomMaximized)
        }
    }

    @Test
    func toggleBottomMaximizedOpensTerminalAndMaximizesWhenBottomIsEmpty() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            harness.show(.project)

            harness.controller.toggleBottomToolWindowMaximized()

            #expect(harness.manager.active(.bottom) == .terminal)
            #expect(harness.manager.bottomMaximized)
        }
    }

    @Test
    func toggleBottomMaximizedKeepsTheActiveBottomWindowAndRestoresOnSecondCall() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            harness.show(.problems)

            harness.controller.toggleBottomToolWindowMaximized()
            let maximized = harness.manager.bottomMaximized
            let keptProblems = harness.manager.active(.bottom) == .problems

            harness.controller.toggleBottomToolWindowMaximized()
            let restored = !harness.manager.bottomMaximized
            let stillProblems = harness.manager.active(.bottom) == .problems

            #expect(maximized)
            #expect(keptProblems)
            #expect(restored)
            #expect(stillProblems)
        }
    }

    @Test
    func determineDesiredCollapseStateWhenHidingAlwaysCollapses() {
        let controller = makeWorkspaceLessController()
        let previousStates: [Bool?] = [nil, true, false]

        for currentlyCollapsed in [true, false] {
            for previous in previousStates {
                let target = controller.determineDesiredCollapseState(
                    shouldHide: true,
                    currentlyCollapsed: currentlyCollapsed,
                    previouslyCollapsed: previous
                )
                #expect(target)
            }
        }
    }

    @Test
    func determineDesiredCollapseStateKeepsVisiblePanelsVisibleWhenRestoring() {
        let controller = makeWorkspaceLessController()
        let previousStates: [Bool?] = [nil, true, false]

        for previous in previousStates {
            let target = controller.determineDesiredCollapseState(
                shouldHide: false,
                currentlyCollapsed: false,
                previouslyCollapsed: previous
            )
            #expect(!target)
        }
    }

    @Test
    func determineDesiredCollapseStateRestoresRememberedStateOfCollapsedPanels() {
        let controller = makeWorkspaceLessController()

        let rememberedCollapsed = controller.determineDesiredCollapseState(
            shouldHide: false,
            currentlyCollapsed: true,
            previouslyCollapsed: true
        )
        let rememberedVisible = controller.determineDesiredCollapseState(
            shouldHide: false,
            currentlyCollapsed: true,
            previouslyCollapsed: false
        )
        let nothingRemembered = controller.determineDesiredCollapseState(
            shouldHide: false,
            currentlyCollapsed: true,
            previouslyCollapsed: nil
        )

        #expect(rememberedCollapsed)
        #expect(!rememberedVisible)
        #expect(!nothingRemembered)
    }

    @Test
    func storeInterfaceCollapseStateRecordsEveryPanelAndResetClearsThem() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            harness.show(.project)

            harness.controller.storeInterfaceCollapseState()

            #expect(harness.controller.prevLeftToolWindowHidden == false)
            #expect(harness.controller.prevBottomToolWindowHidden == true)
            #expect(harness.controller.prevToolbarCollapsed == false)

            harness.controller.resetStoredInterfaceCollapseState()

            #expect(harness.controller.prevLeftToolWindowHidden == nil)
            #expect(harness.controller.prevBottomToolWindowHidden == nil)
            #expect(harness.controller.prevToolbarCollapsed == nil)
        }
    }

    @Test
    func hidingTheInterfaceCollapsesToolWindowsAndToolbarAndRemembersWhatWasVisible() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            harness.show(.project, .terminal)

            harness.controller.toggleInterface(shouldHide: true)

            #expect(harness.manager.active(.left) == nil)
            #expect(harness.manager.active(.bottom) == nil)
            #expect(harness.controller.toolbarCollapsed)
            #expect(harness.controller.prevLeftToolWindowHidden == false)
            #expect(harness.controller.prevBottomToolWindowHidden == false)
            #expect(harness.controller.prevToolbarCollapsed == false)
            #expect(harness.controller.isInterfaceStillHidden())
        }
    }

    @Test
    func hidingTheInterfacePersistsToolbarCollapsedInWorkspaceState() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            harness.show(.project)

            harness.controller.toggleInterface(shouldHide: true)

            let stored = harness.workspace.getFromWorkspaceState(.toolbarCollapsed) as? Bool
            #expect(stored == true)
        }
    }

    @Test
    func restoringTheInterfaceBringsBackWhatWasVisibleAndClearsRememberedState() async throws {
        try await withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            harness.show(.project, .terminal)
            harness.controller.toggleInterface(shouldHide: true)

            harness.controller.toggleInterface(shouldHide: false)

            #expect(harness.manager.active(.left) != nil)
            #expect(harness.manager.active(.bottom) != nil)
            #expect(!harness.controller.toolbarCollapsed)
            let storedAfterRestore = harness.workspace.getFromWorkspaceState(.toolbarCollapsed) as? Bool
            #expect(storedAfterRestore == false)

            let stillHidden = harness.controller.isInterfaceStillHidden()
            #expect(!stillHidden)
            await waitUntil {
                harness.controller.prevLeftToolWindowHidden == nil
                    && harness.controller.prevBottomToolWindowHidden == nil
                    && harness.controller.prevToolbarCollapsed == nil
            }
        }
    }

    @Test
    func restoringTheInterfaceKeepsPanelsThatWereHiddenBeforeHidingHidden() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            harness.show(.project)
            harness.controller.toggleToolbar()
            harness.controller.toggleInterface(shouldHide: true)

            harness.controller.toggleInterface(shouldHide: false)

            #expect(harness.manager.active(.left) != nil)
            #expect(harness.manager.active(.bottom) == nil)
            #expect(harness.controller.toolbarCollapsed)
        }
    }

    @Test
    func hidingTheInterfaceTwiceKeepsEverythingHidden() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            harness.show(.project, .terminal)

            harness.controller.toggleInterface(shouldHide: true)
            harness.controller.toggleInterface(shouldHide: true)

            #expect(harness.manager.active(.left) == nil)
            #expect(harness.manager.active(.bottom) == nil)
            #expect(harness.controller.toolbarCollapsed)
        }
    }

    @Test
    func interfaceCountsAsHiddenWithoutRememberedStateOnlyWhenEveryPanelIsCollapsed() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            harness.manager.hideAll()
            harness.controller.toggleToolbar()
            let allCollapsed = harness.controller.isInterfaceStillHidden()

            harness.manager.show(.project)
            let leftVisible = harness.controller.isInterfaceStillHidden()

            #expect(allCollapsed)
            #expect(!leftVisible)
        }
    }

    @Test
    func interfaceStaysHiddenWhileAnyPreviouslyVisiblePanelIsStillCollapsed() async throws {
        try await withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            harness.show(.project, .terminal)
            harness.controller.toggleInterface(shouldHide: true)

            harness.controller.toggleLeftPanel()
            let stillHidden = harness.controller.isInterfaceStillHidden()
            try await Task.sleep(for: .milliseconds(50))

            #expect(stillHidden)
            #expect(harness.controller.prevLeftToolWindowHidden == false)
            #expect(harness.controller.prevBottomToolWindowHidden == false)
            #expect(harness.controller.prevToolbarCollapsed == false)
        }
    }

    @Test
    func interfaceIsNoLongerHiddenOnceEveryPreviouslyVisiblePanelWasRestoredManually() async throws {
        try await withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            harness.show(.project, .terminal)
            harness.controller.toggleInterface(shouldHide: true)

            harness.controller.toggleLeftPanel()
            harness.controller.toggleLastPanel()
            harness.controller.toggleToolbar()
            let stillHidden = harness.controller.isInterfaceStillHidden()

            #expect(!stillHidden)
            await waitUntil { harness.controller.prevLeftToolWindowHidden == nil }
            #expect(harness.controller.prevBottomToolWindowHidden == nil)
            #expect(harness.controller.prevToolbarCollapsed == nil)
        }
    }

    @Test
    func workspaceLessControllerTreatsToolWindowsAsCollapsed() {
        let controller = makeWorkspaceLessController()
        defer { controller.window?.close() }

        let withToolbarVisible = controller.isInterfaceStillHidden()
        controller.toolbarCollapsed = true
        let withToolbarCollapsed = controller.isInterfaceStillHidden()

        #expect(!withToolbarVisible)
        #expect(withToolbarCollapsed)
    }

    @Test
    func workspaceLessControllerIgnoresToolWindowActions() {
        let controller = makeWorkspaceLessController()
        defer { controller.window?.close() }

        controller.toggleFirstPanel()
        controller.toggleLastPanel()
        controller.toggleLeftPanel()
        controller.toggleToolWindow(.find)
        controller.hideAllToolWindows()
        controller.toggleBottomToolWindowMaximized()

        #expect(controller.workspace == nil)
        #expect(!controller.toolbarCollapsed)
        #expect(controller.prevLeftToolWindowHidden == nil)
    }
}
