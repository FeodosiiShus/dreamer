import Foundation
import Testing
@testable import Dreamder

@MainActor @Suite(.uiGate)
struct ToolWindowLayoutTests {
    @Test
    func storedToolWindowFallsBackToDefaultWhenMissing() {
        #expect(ToolWindowLayout.storedToolWindow(nil, default: .project) == .project)
        #expect(ToolWindowLayout.storedToolWindow(nil, default: nil) == nil)
    }

    @Test
    func storedToolWindowDecodesRawValue() {
        #expect(ToolWindowLayout.storedToolWindow("terminal", default: .project) == .terminal)
        #expect(ToolWindowLayout.storedToolWindow("git", default: nil) == .git)
    }

    @Test
    func emptyStoredToolWindowMeansHidden() {
        #expect(ToolWindowLayout.storedToolWindow("", default: .project) == nil)
        #expect(ToolWindowLayout.storedToolWindow("unknown", default: .project) == nil)
    }

    @Test
    func leftWidthKeepsEditorWidthWhenWindowIsNarrow() {
        let availableWidth: CGFloat = 700
        let width = ToolWindowLayout.clampLeftWidth(ToolWindowLayout.maxLeftWidth, availableWidth: availableWidth)
        let editorWidth = availableWidth - width

        #expect(editorWidth >= ToolWindowLayout.minEditorWidth)
        #expect(editorWidth <= ToolWindowLayout.minEditorWidth)
        #expect(width >= ToolWindowLayout.minLeftWidth)
    }

    @Test
    func leftWidthNeverExceedsMaximum() {
        #expect(ToolWindowLayout.clampLeftWidth(5000, availableWidth: 4000) == ToolWindowLayout.maxLeftWidth)
    }

    @Test
    func leftWidthNeverGoesBelowMinimum() {
        #expect(ToolWindowLayout.clampLeftWidth(40, availableWidth: 1200) == ToolWindowLayout.minLeftWidth)
        #expect(ToolWindowLayout.clampLeftWidth(40, availableWidth: 200) == ToolWindowLayout.minLeftWidth)
    }

    @Test
    func bottomHeightKeepsEditorHeightWhenWindowIsShort() {
        let availableHeight: CGFloat = 500
        let height = ToolWindowLayout.clampBottomHeight(600, availableHeight: availableHeight)
        let editorHeight = availableHeight - height

        #expect(editorHeight >= ToolWindowLayout.minEditorHeight)
        #expect(editorHeight <= ToolWindowLayout.minEditorHeight)
        #expect(height >= ToolWindowLayout.minBottomHeight)
    }

    @Test
    func bottomHeightNeverGoesBelowMinimum() {
        #expect(ToolWindowLayout.clampBottomHeight(10, availableHeight: 900) == ToolWindowLayout.minBottomHeight)
        #expect(ToolWindowLayout.clampBottomHeight(10, availableHeight: 60) == ToolWindowLayout.minBottomHeight)
    }

    @Test
    func applyRestoresAnchorsAndDropsInvalidMaximize() {
        let manager = ToolWindowManager()
        let layout = ToolWindowLayout(
            left: nil,
            bottom: nil,
            leftWidth: 320,
            bottomHeight: 240,
            bottomMaximized: true
        )

        layout.apply(to: manager)

        #expect(manager.active(.left) == nil)
        #expect(manager.active(.bottom) == nil)
        #expect(manager.leftWidth == 320)
        #expect(manager.bottomHeight == 240)
        #expect(!manager.bottomMaximized)
    }

    @Test
    func applyIgnoresWindowFromWrongAnchor() {
        let manager = ToolWindowManager()
        let layout = ToolWindowLayout(
            left: .terminal,
            bottom: .project,
            leftWidth: 300,
            bottomHeight: 300,
            bottomMaximized: false
        )

        layout.apply(to: manager)

        #expect(manager.active(.left) == nil)
        #expect(manager.active(.bottom) == nil)
    }

    @Test
    func layoutRoundTripsFromManager() {
        let manager = ToolWindowManager()
        manager.show(.git)
        manager.leftWidth = 412
        manager.bottomHeight = 210
        manager.bottomMaximized = true

        let layout = ToolWindowLayout(manager: manager)

        #expect(layout.left == .project)
        #expect(layout.bottom == .git)
        #expect(layout.leftWidth == 412)
        #expect(layout.bottomHeight == 210)
        #expect(layout.bottomMaximized)
    }

    @Test
    func layoutRoundTripsSplitWindowsAndWeights() {
        let manager = ToolWindowManager()
        manager.setSplit(.find, true)
        manager.show(.find)
        manager.setSplit(.commit, true)
        manager.show(.commit)
        manager.setMainProportion(on: .bottom, 0.65)

        let layout = ToolWindowLayout(manager: manager)

        #expect(layout.bottom == .terminal)
        #expect(layout.bottomSplit == .find)
        #expect(layout.left == .project)
        #expect(layout.leftSplit == .commit)
        #expect(layout.splitWindows == [.commit, .find])
        #expect(abs((layout.sideWeights[.find] ?? 0) - 0.35) < 1e-9)

        let restored = ToolWindowManager()
        layout.apply(to: restored)

        #expect(restored.visible(on: .bottom, side: .split) == .find)
        #expect(restored.visible(on: .left, side: .split) == .commit)
        #expect(abs(restored.mainProportion(on: .bottom) - 0.65) < 1e-9)
        #expect(ToolWindowLayout(manager: restored) == layout)
    }

    @Test
    func layoutWithoutSplitFieldsRestoresTheOldTwoSlotLayout() {
        let manager = ToolWindowManager()
        let layout = ToolWindowLayout(
            left: .commit,
            bottom: .git,
            leftWidth: 300,
            bottomHeight: 250,
            bottomMaximized: true
        )

        layout.apply(to: manager)

        #expect(manager.visible(on: .left, side: .main) == .commit)
        #expect(manager.visible(on: .bottom, side: .main) == .git)
        #expect(manager.visible(on: .left, side: .split) == nil)
        #expect(manager.visible(on: .bottom, side: .split) == nil)
        #expect(manager.bottomMaximized)
    }

    @Test
    func applyClearsSplitFlagsThatTheLayoutDoesNotList() {
        let manager = ToolWindowManager()
        manager.setSplit(.find, true)
        manager.setSideWeight(.find, 0.2)

        ToolWindowLayout(
            left: nil,
            bottom: nil,
            leftWidth: 300,
            bottomHeight: 300,
            bottomMaximized: false
        ).apply(to: manager)

        #expect(manager.isSplit(.find) == false)
        #expect(manager.sideWeight(of: .find) == ToolWindowSplitState.defaultSideWeight)
    }

    @Test
    func applyIgnoresWindowStoredOnTheWrongSide() {
        let manager = ToolWindowManager()
        let layout = ToolWindowLayout(
            left: .project,
            bottom: nil,
            leftWidth: 300,
            bottomHeight: 300,
            bottomMaximized: false,
            leftSplit: .commit,
            bottomSplit: nil,
            splitWindows: [.project],
            sideWeights: [:]
        )

        layout.apply(to: manager)

        #expect(manager.visible(on: .left, side: .main) == nil)
        #expect(manager.visible(on: .left, side: .split) == nil)
    }

    @Test
    func maximizedBottomIsValidWithOnlyASplitWindowShown() {
        let manager = ToolWindowManager()
        let layout = ToolWindowLayout(
            left: nil,
            bottom: nil,
            leftWidth: 300,
            bottomHeight: 300,
            bottomMaximized: true,
            leftSplit: nil,
            bottomSplit: .git,
            splitWindows: [.git],
            sideWeights: [:]
        )

        layout.apply(to: manager)

        #expect(manager.active(.bottom) == .git)
        #expect(manager.bottomMaximized)
    }

    @Test
    func storedSplitWindowsDropUnknownIdentifiers() {
        #expect(ToolWindowLayout.storedSplitWindows(["find", "bogus", "git"]) == [.find, .git])
        #expect(ToolWindowLayout.storedSplitWindows(nil) == [])
        #expect(ToolWindowLayout.storedSplitWindows("find") == [])
    }

    @Test
    func storedSideWeightsDropUnknownIdentifiers() {
        let weights = ToolWindowLayout.storedSideWeights(["find": 0.25, "bogus": 0.9])
        #expect(weights == [.find: 0.25])
        #expect(ToolWindowLayout.storedSideWeights(nil).isEmpty)
    }
}
