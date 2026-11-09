//
//  MenuWithButtonStyle.swift
//  Dreamder
//
//  Created by Tommy Ludwig on 08.09.24.
//

import SwiftUI

/// A menu styled to resemble a bordered button.
struct MenuWithButtonStyle<MenuView: View>: View {
    static var width: CGFloat { 30 }

    var systemImage: String
    var menu: () -> MenuView
    @State private var hover: MainToolbarHoverState

    init(
        systemImage: String,
        menu: @escaping () -> MenuView,
        hover: MainToolbarHoverState = MainToolbarHoverState()
    ) {
        self.systemImage = systemImage
        self.menu = menu
        _hover = State(initialValue: hover)
    }

    var body: some View {
        Menu {
            menu()
        } label: {
            MenuWithButtonLabel(systemImage: systemImage, isHovering: hover.isHovering)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: Self.width)
        .onHover(perform: hover.setHovering)
    }
}

struct MenuWithButtonLabel: View {
    let systemImage: String
    let isHovering: Bool

    var body: some View {
        ActionButtonChrome(look: .standard, isHovering: isHovering, isPressed: false) {
            HStack {
                Image(systemName: systemImage)
                Image(systemName: "chevron.down")
                    .resizable()
                    .fontWeight(.bold)
                    .frame(width: 8, height: 4.8)
                    .padding(.leading, -1.5)
                    .padding(.trailing, -2)
            }
            .frame(width: 30, height: Islands.actionButtonSize)
        }
    }
}
