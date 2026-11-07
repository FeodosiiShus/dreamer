import CoreGraphics
import Foundation
import Testing
@testable import Dreamder

@MainActor @Suite
struct ToolWindowSplitTests {
    @Test
    func defaultStateShowsProjectOnLeftAndTerminalOnBottom() {
        let state = ToolWindowSplitState()
        #expect(state.window(at: ToolWindowSlot(.left, .main)) == .project)
        #expect(state.window(at: ToolWindowSlot(.bottom, .main)) == .terminal)
        #expect(state.window(at: ToolWindowSlot(.left, .split)) == nil)
        #expect(state.window(at: ToolWindowSlot(.bottom, .split)) == nil)
        #expect(state.splitWindows.isEmpty)
    }

    @Test
    func slotCombinesAnchorWithSplitFlag() {
        var state = ToolWindowSplitState()
        #expect(state.slot(of: .find) == ToolWindowSlot(.bottom, .main))
        state.setSplit(.find, true)
        #expect(state.slot(of: .find) == ToolWindowSlot(.bottom, .split))
        #expect(state.slot(of: .commit) == ToolWindowSlot(.left, .main))
    }

    @Test
    func showingReplacesOnlyTheWindowOnTheSameAnchorAndSide() {
        var state = ToolWindowSplitState(visible: [:])
        state.setSplit(.problems, true)
        state.show(.run)
        state.show(.problems)
        state.show(.terminal)
        #expect(state.window(at: ToolWindowSlot(.bottom, .main)) == .terminal)
        #expect(state.window(at: ToolWindowSlot(.bottom, .split)) == .problems)
        #expect(!state.isVisible(.run))
    }

    @Test
    func hidingAWindowThatIsNotShownKeepsTheOccupant() {
        var state = ToolWindowSplitState()
        state.hide(.git)
        #expect(state.isVisible(.terminal))
    }

    @Test
    func hidingAnAnchorClearsBothSides() {
        var state = ToolWindowSplitState()
        state.setSplit(.find, true)
        state.show(.find)
        state.hide(anchor: .bottom)
        #expect(!state.hasVisibleWindow(on: .bottom))
        #expect(state.hasVisibleWindow(on: .left))
        #expect(state.isSplit(.find))
    }

    @Test
    func togglingSplitOnVisibleWindowMovesItAcrossSides() {
        var state = ToolWindowSplitState()
        state.setSplit(.terminal, true)
        #expect(state.window(at: ToolWindowSlot(.bottom, .split)) == .terminal)
        #expect(state.window(at: ToolWindowSlot(.bottom, .main)) == nil)
        state.setSplit(.terminal, false)
        #expect(state.window(at: ToolWindowSlot(.bottom, .main)) == .terminal)
        #expect(state.window(at: ToolWindowSlot(.bottom, .split)) == nil)
    }

    @Test
    func togglingSplitOnHiddenWindowDoesNotShowIt() {
        var state = ToolWindowSplitState()
        state.setSplit(.git, true)
        #expect(!state.isVisible(.git))
        #expect(state.isSplit(.git))
    }

    @Test
    func settingTheSameSplitValueChangesNothing() {
        var state = ToolWindowSplitState()
        let before = state
        state.setSplit(.terminal, false)
        #expect(state == before)
    }

    @Test
    func sideBySideNeedsBothSides() {
        var state = ToolWindowSplitState()
        #expect(!state.isShownSideBySide(on: .bottom))
        state.setSplit(.find, true)
        state.show(.find)
        #expect(state.isShownSideBySide(on: .bottom))
        #expect(!state.isShownSideBySide(on: .left))
    }

    @Test
    func normalizeWeightFallsBackToDefaultOutsideOpenRange() {
        #expect(ToolWindowSplitState.normalizeWeight(0) == ToolWindowSplitState.defaultWeight)
        #expect(ToolWindowSplitState.normalizeWeight(-1) == ToolWindowSplitState.defaultWeight)
        #expect(ToolWindowSplitState.normalizeWeight(1) == 1 - ToolWindowSplitState.defaultWeight)
        #expect(ToolWindowSplitState.normalizeWeight(4) == 1 - ToolWindowSplitState.defaultWeight)
        #expect(ToolWindowSplitState.normalizeWeight(0.4) == 0.4)
    }

    @Test
    func sideWeightIsClampedAndDefaultIsNotStored() {
        var state = ToolWindowSplitState()
        state.setSideWeight(.find, 7)
        #expect(state.sideWeight(of: .find) == 1)
        state.setSideWeight(.find, -3)
        #expect(state.sideWeight(of: .find) == 0)
        state.setSideWeight(.find, ToolWindowSplitState.defaultSideWeight)
        #expect(state.customSideWeights.isEmpty)
    }

    @Test
    func proportionIsOneWithoutASibling() {
        let state = ToolWindowSplitState()
        #expect(state.mainProportion(on: .bottom) == 1)
    }

    @Test
    func proportionIsHalfWithDefaultSideWeights() {
        var state = ToolWindowSplitState()
        state.setSplit(.find, true)
        state.show(.find)
        #expect(state.mainProportion(on: .bottom) == 0.5)
    }

    @Test
    func proportionDividesMainWeightByTotal() {
        var state = ToolWindowSplitState()
        state.setSplit(.find, true)
        state.show(.find)
        state.setSideWeight(.terminal, 0.3)
        state.setSideWeight(.find, 0.9)
        #expect(abs(state.mainProportion(on: .bottom) - 0.25) < 1e-9)
    }

    @Test
    func proportionOutsideOpenRangeFallsBackToDefaultWeight() {
        var state = ToolWindowSplitState()
        state.setSplit(.find, true)
        state.show(.find)
        state.setSideWeight(.terminal, 1)
        state.setSideWeight(.find, 0)
        #expect(state.mainProportion(on: .bottom) == 1 - ToolWindowSplitState.defaultWeight)
    }

    @Test
    func settingProportionStoresComplementaryWeights() {
        var state = ToolWindowSplitState()
        state.setSplit(.commit, true)
        state.show(.commit)
        state.setMainProportion(on: .left, 0.4)
        #expect(state.sideWeight(of: .project) == 0.4)
        #expect(abs(state.sideWeight(of: .commit) - 0.6) < 1e-9)
        #expect(abs(state.mainProportion(on: .left) - 0.4) < 1e-9)
    }

    @Test
    func settingProportionWithoutSiblingIsIgnored() {
        var state = ToolWindowSplitState()
        state.setMainProportion(on: .left, 0.2)
        #expect(state.customSideWeights.isEmpty)
    }

    @Test
    func stripeGroupsKeepOrderAndPutSplitWindowsLast() {
        var state = ToolWindowSplitState()
        state.setSplit(.run, true)
        state.setSplit(.problems, true)
        let groups = state.stripeGroups(on: .bottom, ordered: ToolWindowID.allCases)
        #expect(groups.main == [.find, .terminal, .git, .languageServices])
        #expect(groups.split == [.run, .problems])
    }

    @Test
    func stripeGroupsOnlyContainWindowsOfTheirAnchor() {
        var state = ToolWindowSplitState()
        state.setSplit(.commit, true)
        let groups = state.stripeGroups(on: .left, ordered: ToolWindowID.allCases)
        #expect(groups.main == [.project, .structure])
        #expect(groups.split == [.commit])
    }

    @Test
    func stripeGroupsFollowTheGivenOrder() {
        let state = ToolWindowSplitState()
        let groups = state.stripeGroups(on: .bottom, ordered: [.terminal, .run, .project])
        #expect(groups.main == [.terminal, .run])
        #expect(groups.split.isEmpty)
    }

    @Test
    func leftAnchorStacksAndBottomAnchorSitsSideBySide() {
        #expect(ToolWindowAnchor.left.splitsVertically)
        #expect(!ToolWindowAnchor.bottom.splitsVertically)
    }

    @Test
    func partSizesSplitTheSpaceMinusTheGap() {
        let sizes = ToolWindowSplitState.partSizes(total: 504, proportion: 0.25, gap: 4, minimumPart: 50)
        #expect(sizes.first == 125)
        #expect(sizes.second == 375)
    }

    @Test
    func partSizesRespectTheMinimumOnBothSides() {
        let small = ToolWindowSplitState.partSizes(total: 404, proportion: 0.01, gap: 4, minimumPart: 100)
        #expect(small.first == 100)
        #expect(small.second == 300)
        let large = ToolWindowSplitState.partSizes(total: 404, proportion: 0.99, gap: 4, minimumPart: 100)
        #expect(large.first == 300)
        #expect(large.second == 100)
    }

    @Test
    func partSizesShrinkTheMinimumInATinyArea() {
        let sizes = ToolWindowSplitState.partSizes(total: 54, proportion: 0.5, gap: 4, minimumPart: 100)
        #expect(sizes.first == 25)
        #expect(sizes.second == 25)
    }

    @Test
    func draggingTheDividerMovesTheProportion() {
        let proportion = ToolWindowSplitState.proportion(
            movingDividerBy: 50,
            from: 0.5,
            total: 404,
            gap: 4,
            minimumPart: 100
        )
        #expect(abs(proportion - 0.625) < 1e-9)
    }

    @Test
    func draggingTheDividerStopsAtTheMinimums() {
        let up = ToolWindowSplitState.proportion(
            movingDividerBy: -1000,
            from: 0.5,
            total: 404,
            gap: 4,
            minimumPart: 100
        )
        #expect(abs(up - 0.25) < 1e-9)
        let down = ToolWindowSplitState.proportion(
            movingDividerBy: 1000,
            from: 0.5,
            total: 404,
            gap: 4,
            minimumPart: 100
        )
        #expect(abs(down - 0.75) < 1e-9)
    }

    @Test
    func draggingInAnEmptyAreaReturnsTheDefaultSideWeight() {
        let proportion = ToolWindowSplitState.proportion(
            movingDividerBy: 10,
            from: 0.7,
            total: 4,
            gap: 4,
            minimumPart: 100
        )
        #expect(proportion == ToolWindowSplitState.defaultSideWeight)
    }
}
