import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct EditorTabAppearanceTests {
    @Test
    func metricsFollowTheIslandsTabPainter() {
        #expect(Islands.tabPillHeight == (Islands.isCompact ? 24 : 28))
        #expect(Islands.tabPillRadius == ActionButtonLook.mainToolbarButton.cornerRadius)
        #expect(EditorTabMetrics.leadingInset == (Islands.isCompact ? 6 : 8))
        #expect(EditorTabMetrics.trailingInset == (Islands.isCompact ? 4 : 8))
        #expect(EditorTabMetrics.iconTextGap == 4)
        #expect(EditorTabMetrics.actionsLeadingGap == 2)
        #expect(EditorTabMetrics.iconSize == 16)
        #expect(EditorTabMetrics.closeButtonSize == 16)
        #expect(EditorTabClosePressModel.buttonSize == EditorTabMetrics.closeButtonSize)
        #expect(EditorTabMetrics.accessoryButtonSize == CGSize(width: 26, height: 24))
        #expect(Islands.actionIconSize == 16)
        #expect(Islands.actionButtonSize == 22)
        #expect(EditorTabView.tabHeight == Islands.tabPillHeight)
    }

    @Test
    func selectedActiveTabsKeepTheirColoursWhileHovered() {
        let resting = EditorTabAppearance.resolve(isSelected: true, isFocused: true, isHovering: false)
        let hovered = EditorTabAppearance.resolve(isSelected: true, isFocused: true, isHovering: true)

        #expect(resting.fill == Islands.tabSelectedBackground)
        #expect(resting.border == Islands.tabSelectedBorder)
        #expect(hovered == resting)
    }

    @Test
    func selectedInactiveTabsShowTheHoverFillWithTheInactiveBorderWhileHovered() {
        let resting = EditorTabAppearance.resolve(isSelected: true, isFocused: false, isHovering: false)
        let hovered = EditorTabAppearance.resolve(isSelected: true, isFocused: false, isHovering: true)

        #expect(resting.fill == Islands.tabInactiveSelectedBackground)
        #expect(resting.border == Islands.tabInactiveSelectedBorder)
        #expect(hovered.fill == Islands.actionHover)
        #expect(hovered.border == Islands.tabInactiveSelectedBorder)
    }

    @Test
    func unselectedTabsOnlyPaintTheHoverFillWithoutABorder() {
        let resting = EditorTabAppearance.resolve(isSelected: false, isFocused: true, isHovering: false)
        let hovered = EditorTabAppearance.resolve(isSelected: false, isFocused: false, isHovering: true)

        #expect(resting == EditorTabAppearance(fill: .clear, border: .clear))
        #expect(hovered == EditorTabAppearance(fill: Islands.actionHover, border: .clear))
    }

    private func closeGlyphSnapshot(_ state: ActionButtonState) async throws -> NSBitmapImageRep? {
        let hosted = HostedViewFixture.host(size: NSSize(width: 40, height: 40)) {
            EditorTabCloseGlyph(state: state)
        }
        defer { hosted.close() }
        try await hosted.settle(.milliseconds(100))
        #expect(hosted.renders())
        return hosted.snapshot()
    }

    @Test
    func closeGlyphRendersEveryState() async throws {
        let normal = try await closeGlyphSnapshot(.normal)
        let hovered = try await closeGlyphSnapshot(.hovered)
        let pressed = try await closeGlyphSnapshot(.pressed)

        #expect(HostedView.pixelsDiffer(normal, hovered))
        #expect(HostedView.pixelsDiffer(hovered, pressed))
    }

    @Test
    func accessoryIconsPaintTheActionButtonHoverBackground() async throws {
        let size = NSSize(width: 60, height: 50)
        let idle = HostedViewFixture.host(size: size) {
            EditorTabBarAccessoryIcon(icon: "general/moreVertical", isHovering: false)
        }
        let hovered = HostedViewFixture.host(size: size) {
            EditorTabBarAccessoryIcon(icon: "general/moreVertical", isHovering: true)
        }
        defer {
            idle.close()
            hovered.close()
        }
        try await idle.settle(.milliseconds(100))
        try await hovered.settle(.milliseconds(100))

        #expect(idle.renders())
        #expect(HostedView.pixelsDiffer(idle.snapshot(), hovered.snapshot()))
        #expect(ActionButtonLook.standard.fills(for: .hovered) == [Islands.actionHover])
    }

    @Test
    func trailingAccessoriesRenderTheirMenuButton() async throws {
        try await withTempDir { directory in
            let workspace = try HostedViewFixture.makeWorkspace(in: directory)
            defer { workspace.close() }
            let editor = try #require(workspace.editorManager?.activeEditor)
            let hosted = try HostedViewFixture.hostInWorkspace(workspace, size: NSSize(width: 120, height: 50)) {
                EditorTabBarTrailingAccessories(isHovering: true).environment(editor)
            }
            defer { hosted.close() }
            try await hosted.settle(.milliseconds(100))

            #expect(hosted.renders())
        }
    }

    @Test
    func closeButtonGlyphFollowsHover() {
        let flags = EditorTabsCoverageFlags()
        let button = EditorTabCloseButton(
            closeAction: {},
            closeButtonGestureActive: Bindable(flags).gestureActive,
            isHoveringClose: Bindable(flags).hovering
        )

        #expect(button.glyphState == .normal)
        flags.hovering = true
        #expect(button.glyphState == .hovered)
    }

    @Test
    func hiddenTabsButtonTracksHover() {
        let strip = EditorTabStripModel()
        #expect(!strip.isHoveringHiddenTabsButton)

        strip.setHoveringHiddenTabsButton(true)
        #expect(strip.isHoveringHiddenTabsButton)

        strip.setHoveringHiddenTabsButton(false)
        #expect(!strip.isHoveringHiddenTabsButton)
    }
}
