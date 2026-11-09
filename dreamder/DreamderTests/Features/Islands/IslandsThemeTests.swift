import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct IslandsThemeTests {
    @Test
    func densitiesExposeIdentifiersAndTitles() {
        #expect(Islands.Density.allCases.map(\.id) == ["compact", "default"])
        #expect(Islands.Density.allCases.map(\.title) == ["Compact", "Default"])
    }

    @Test
    func metricsAreSelectedPerDensityAndStayPositive() {
        let metrics: [CGFloat] = [
            Islands.islandRadius,
            Islands.islandGap,
            Islands.mainToolbarHeight,
            Islands.toolbarControlHeight,
            Islands.toolWindowHeaderHeight,
            Islands.tabStripHeight,
            Islands.tabBarHeight,
            Islands.tabPillHeight,
            Islands.tabPillRadius,
            Islands.tabColorInset,
            Islands.tabLabelFontSize,
            Islands.statusBarHeight,
            Islands.stripeWidth,
            Islands.stripeButtonWidth,
            Islands.stripeButtonHeight,
            Islands.stripeButtonCellHeight,
            Islands.stripeButtonRadius,
            Islands.stripeSeparatorWidth,
            Islands.stripeSeparatorCellHeight,
            Islands.actionButtonSize,
            Islands.actionButtonRadius,
            Islands.actionIconSize,
            Islands.headerLabelLeadingInset,
            Islands.headerLabelTrailingInset,
            Islands.headerToolbarLeadingInset,
            Islands.headerToolbarTrailingInset,
            Islands.headerTabHorizontalInset,
            Islands.stripeIconSize,
            Islands.treeRowHeight,
            Islands.listRowHeight,
            Islands.popupRowHeight,
            Islands.popupHeaderHeight,
            Islands.popupFooterHeight
        ]
        #expect(metrics.allSatisfy { $0 > 0 })
        #expect(Islands.tabBarHeight == Islands.tabStripHeight + 1)
        #expect(Islands.density == .compact || Islands.density == .default)
        #expect(Islands.isCompact == (Islands.density == .compact))
    }

    @Test
    func glassTintsFontsAndIconsResolve() {
        let colors: [Color] = [
            Islands.glassIslandTint,
            Islands.glassPopupTint,
            Islands.stripeSelectedForeground,
            Islands.stripeSeparator,
            Islands.underTabsBorder,
            Islands.glassRaisedFill,
            Islands.glassFieldFill
        ]
        #expect(colors.count == 7)

        let fonts: [Font] = [
            Islands.uiFont,
            Islands.smallFont,
            Islands.headerTitleFont,
            Islands.toolWindowTitleFont,
            Islands.tabLabelFont,
            Islands.codeFont
        ]
        #expect(fonts.count == 6)
        #expect(Islands.codeNSFont.pointSize == Islands.codeFontSize)
        _ = IntelliJIcon.image("general/search")
        _ = IntelliJIcon.nsImage("general/search")
    }
}
