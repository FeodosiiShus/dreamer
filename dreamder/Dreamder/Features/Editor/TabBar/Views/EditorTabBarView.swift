//
//  EditorTabBarView.swift
//  Dreamder
//
//  Created by Lukas Pistrol and Lingxi Li on 17.03.22.
//

import SwiftUI

struct EditorTabBarView: View {
    static var height: CGFloat {
        Islands.tabBarHeight
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                EditorTabs()
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Tab Bar")
                    .accessibilityIdentifier("TabBar")
                EditorTabBarTrailingAccessories()
            }
            .frame(height: Islands.tabStripHeight)
            .padding(.horizontal, 4)
            Rectangle()
                .fill(Islands.frame)
                .frame(height: 1)
        }
    }
}
