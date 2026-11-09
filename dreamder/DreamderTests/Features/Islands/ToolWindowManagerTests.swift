import Foundation
import Testing
@testable import Dreamder

@MainActor @Suite(.uiGate)
struct ToolWindowManagerTests {
    @Test
    func toggleHidesVisibleWindowAndShowsItAgain() {
        let manager = ToolWindowManager()
        manager.show(.git)
        manager.toggle(.git)
        #expect(manager.active(.bottom) == nil)
        manager.toggle(.git)
        #expect(manager.active(.bottom) == .git)
    }

    @Test
    func showingReplacesOnlyTheSameAnchor() {
        let manager = ToolWindowManager()
        manager.show(.commit)
        manager.show(.problems)
        manager.show(.terminal)
        #expect(manager.active(.left) == .commit)
        #expect(manager.active(.bottom) == .terminal)
        #expect(manager.isVisible(.problems) == false)
    }

    @Test
    func togglingAHiddenWindowSwitchesTheAnchorToIt() {
        let manager = ToolWindowManager()
        manager.show(.run)
        manager.toggle(.find)
        #expect(manager.active(.bottom) == .find)
        #expect(manager.isVisible(.run) == false)
    }

    @Test
    func hidingBottomClearsMaximizedButHidingLeftKeepsIt() {
        let manager = ToolWindowManager()
        manager.show(.terminal)
        manager.bottomMaximized = true
        manager.hide(.left)
        #expect(manager.bottomMaximized)
        manager.hide(.bottom)
        #expect(manager.bottomMaximized == false)
        #expect(manager.active(.bottom) == nil)
    }

    @Test
    func hideAllClosesEveryAnchorAndRestoresBottomSize() {
        let manager = ToolWindowManager()
        manager.show(.structure)
        manager.show(.git)
        manager.bottomMaximized = true
        manager.hideAll()
        #expect(manager.visibleWindows.isEmpty)
        #expect(manager.bottomMaximized == false)
    }

    @Test
    func windowsDockWhereIntelliJDocksThem() {
        let left = ToolWindowID.allCases.filter { $0.anchor == .left }
        let bottom = ToolWindowID.allCases.filter { $0.anchor == .bottom }
        #expect(left == [.project, .commit, .structure])
        #expect(bottom == [.run, .find, .terminal, .problems, .git, .languageServices])
    }

    @Test
    func everyWindowHasDistinctTitleAndIcon() {
        let titles = Set(ToolWindowID.allCases.map(\.title))
        let icons = Set(ToolWindowID.allCases.map(\.icon))
        #expect(titles.count == ToolWindowID.allCases.count)
        #expect(icons.count == ToolWindowID.allCases.count)
    }

    @Test
    func defaultLayoutShowsProjectAndTerminalOnTheMainSide() {
        let manager = ToolWindowManager()
        #expect(manager.visible(on: .left, side: .main) == .project)
        #expect(manager.visible(on: .bottom, side: .main) == .terminal)
        #expect(manager.visible(on: .left, side: .split) == nil)
        #expect(manager.visible(on: .bottom, side: .split) == nil)
    }

    @Test
    func splitWindowIsShownBesideTheMainWindowOfItsAnchor() {
        let manager = ToolWindowManager()
        manager.setSplit(.commit, true)
        manager.show(.commit)
        #expect(manager.visible(on: .left, side: .main) == .project)
        #expect(manager.visible(on: .left, side: .split) == .commit)
        #expect(manager.isVisible(.project))
        #expect(manager.isVisible(.commit))
        #expect(manager.isSplit(.commit))
    }

    @Test
    func showingReplacesOnlyTheSameSide() {
        let manager = ToolWindowManager()
        manager.setSplit(.find, true)
        manager.show(.find)
        manager.show(.problems)
        #expect(manager.visible(on: .bottom, side: .main) == .problems)
        #expect(manager.visible(on: .bottom, side: .split) == .find)
        #expect(manager.isVisible(.terminal) == false)
        manager.setSplit(.git, true)
        manager.show(.git)
        #expect(manager.visible(on: .bottom, side: .split) == .git)
        #expect(manager.isVisible(.find) == false)
    }

    @Test
    func hidingOneIdKeepsTheOtherWindowOnTheSameAnchor() {
        let manager = ToolWindowManager()
        manager.setSplit(.find, true)
        manager.show(.find)
        manager.hide(.terminal)
        #expect(manager.visible(on: .bottom, side: .main) == nil)
        #expect(manager.visible(on: .bottom, side: .split) == .find)
        manager.show(.terminal)
        manager.hide(.find)
        #expect(manager.visible(on: .bottom, side: .main) == .terminal)
        #expect(manager.visible(on: .bottom, side: .split) == nil)
        manager.hide(.find)
        #expect(manager.isVisible(.terminal))
    }

    @Test
    func hidingAnAnchorClosesBothSides() {
        let manager = ToolWindowManager()
        manager.setSplit(.find, true)
        manager.show(.find)
        manager.bottomMaximized = true
        manager.hide(.bottom)
        #expect(manager.active(.bottom) == nil)
        #expect(manager.bottomMaximized == false)
        #expect(manager.isSplit(.find))
    }

    @Test
    func hidingOneWindowKeepsItsSibling() {
        let manager = ToolWindowManager()
        manager.setSplit(.find, true)
        manager.show(.find)
        manager.toggle(.find)
        #expect(manager.visible(on: .bottom, side: .split) == nil)
        #expect(manager.visible(on: .bottom, side: .main) == .terminal)
    }

    @Test
    func activeFallsBackToTheSplitWindowWhenMainSideIsEmpty() {
        let manager = ToolWindowManager()
        manager.setSplit(.find, true)
        manager.show(.find)
        manager.toggle(.terminal)
        #expect(manager.active(.bottom) == .find)
    }

    @Test
    func maximizedFlagSurvivesHidingOneOfTwoBottomWindows() {
        let manager = ToolWindowManager()
        manager.setSplit(.find, true)
        manager.show(.find)
        manager.bottomMaximized = true
        manager.toggle(.find)
        #expect(manager.bottomMaximized)
        manager.toggle(.terminal)
        #expect(manager.bottomMaximized == false)
    }

    @Test
    func movingAVisibleWindowToSplitKeepsItVisibleOnTheNewSide() {
        let manager = ToolWindowManager()
        manager.setSplit(.terminal, true)
        #expect(manager.visible(on: .bottom, side: .split) == .terminal)
        #expect(manager.visible(on: .bottom, side: .main) == nil)
        manager.setSplit(.terminal, false)
        #expect(manager.visible(on: .bottom, side: .main) == .terminal)
    }

    @Test
    func movingToTheSideOfAnOccupiedSlotHidesTheOccupant() {
        let manager = ToolWindowManager()
        manager.setSplit(.terminal, true)
        manager.show(.find)
        manager.setSplit(.find, true)
        #expect(manager.visible(on: .bottom, side: .split) == .find)
        #expect(manager.visible(on: .bottom, side: .main) == nil)
        #expect(manager.isVisible(.terminal) == false)
    }

    @Test
    func mainProportionFollowsDraggedDivider() {
        let manager = ToolWindowManager()
        manager.setSplit(.find, true)
        manager.show(.find)
        #expect(manager.mainProportion(on: .bottom) == 0.5)
        manager.setMainProportion(on: .bottom, 0.7)
        #expect(abs(manager.mainProportion(on: .bottom) - 0.7) < 1e-9)
        #expect(manager.sideWeight(of: .terminal) == 0.7)
        #expect(abs(manager.sideWeight(of: .find) - 0.3) < 1e-9)
    }
}
