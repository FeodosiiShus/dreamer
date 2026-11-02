//
//  StatusBarMenuStyle.swift
//  Dreamder
//
//  Created by Austin Condiff on 3/24/23
//

import SwiftUI

struct StatusBarMenuStyle: MenuStyle {

    func makeBody(configuration: Configuration) -> some View {
        Menu(configuration)
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
    }
}

extension MenuStyle where Self == StatusBarMenuStyle {
    static var statusBar: StatusBarMenuStyle { .init() }
}
