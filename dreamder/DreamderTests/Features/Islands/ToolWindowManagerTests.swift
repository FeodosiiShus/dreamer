import Foundation
import Testing
@testable import Dreamder

@MainActor @Suite
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
        #expect(manager.visible.isEmpty)
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
}
