import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct MainToolbarMetricsTests {
    @Test
    func buttonAndIconSizesFollowJBUI() {
        #expect(MainToolbarMetrics.buttonSize == 30)
        #expect(MainToolbarMetrics.iconSize == 20)
        #expect(MainToolbarMetrics.runIconSize == 16)
        #expect(MainToolbarMetrics.projectAvatarSize == 20)
    }

    @Test
    func dropdownMetricsFollowTheToolbarComboButton() {
        let margin = MainToolbarMetrics.dropdownMargin

        #expect(margin.top == 5)
        #expect(margin.leading == 10)
        #expect(margin.bottom == 5)
        #expect(margin.trailing == 6)
        #expect(MainToolbarMetrics.dropdownIconTextGap == 6)
        #expect(MainToolbarMetrics.chevronGap == 2)
        #expect(MainToolbarMetrics.chevronSize == 16)
        #expect(MainToolbarMetrics.dropdownMaxWidth == 350)
        #expect(MainToolbarMetrics.runWidgetSpacing == 4)
    }

    @Test
    func searchFieldIsATextFieldHeightBoxWithAComponentBorder() {
        #expect(MainToolbarMetrics.searchFieldHeight == Islands.toolbarControlHeight)
        #expect(MainToolbarMetrics.searchFieldRadius == (Islands.isCompact ? 3 : 4))
        #expect(MainToolbarMetrics.searchFieldBorderWidth == 1)
        #expect(MainToolbarMetrics.searchFieldWidth == 260)
        #expect(MainToolbarMetrics.searchFieldIconSize == 16)
        #expect(MainToolbarMetrics.searchFieldIconTextGap == 6)
        #expect(MainToolbarMetrics.searchFieldPadding == 8)
    }

    @Test
    func runWidgetIconColoursFollowTheIslandsTheme() {
        #expect(MainToolbarMetrics.runIconColor == Color(hex: 0x4E9D6C))
        #expect(MainToolbarMetrics.defaultIconColor == Color(hex: 0xC3C5CB))
    }

    @Test
    func dropdownLabelRendersWithAndWithoutALeadingIcon() async throws {
        let size = NSSize(width: 260, height: 50)
        let plain = HostedViewFixture.host(size: size) {
            MainToolbarDropdownLabel(text: "Build")
        }
        let withIcon = HostedViewFixture.host(size: size) {
            MainToolbarDropdownLabel(text: "Build") {
                Image("vcs/branch").resizable().frame(width: 16, height: 16)
            }
        }
        defer {
            plain.close()
            withIcon.close()
        }
        try await plain.settle(.milliseconds(100))
        try await withIcon.settle(.milliseconds(100))

        #expect(plain.renders())
        #expect(withIcon.renders())
        #expect(HostedView.pixelsDiffer(plain.snapshot(), withIcon.snapshot()))
    }
}
