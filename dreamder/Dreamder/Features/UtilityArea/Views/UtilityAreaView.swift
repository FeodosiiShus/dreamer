//
//  UtilityAreaView.swift
//  Dreamder
//
//  Created by Lukas Pistrol on 22.03.22.
//

import SwiftUI

struct UtilityAreaView: View {
    @Environment(UtilityAreaViewModel.self) private var utilityAreaViewModel

    var body: some View {
//        WorkspacePanelView(
//            viewModel: utilityAreaViewModel,
//            selectedTab: $utilityAreaViewModel.selectedTab,
//            tabItems: $utilityAreaViewModel.tabItems,
//            sidebarPosition: .side,
//            darkDivider: true,
//            padSideItemVertically: true
//        )
        utilityAreaViewModel.selectedTab
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Utility Area")
            .accessibilityIdentifier("UtilityArea")
    }
}
