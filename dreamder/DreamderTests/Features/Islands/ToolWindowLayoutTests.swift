import Foundation
import Testing
@testable import Dreamder

@MainActor @Suite
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
}
