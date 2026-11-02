//
//  EditorTabCloseButton.swift
//  Dreamder
//
//  Created by Austin Condiff on 1/17/23.
//

import SwiftUI

struct EditorTabCloseButton: View {
    var closeAction: () -> Void
    @Binding var closeButtonGestureActive: Bool
    @Binding var isHoveringClose: Bool

    @State private var isPressingClose: Bool = false

    private let buttonSize: CGFloat = 16

    var body: some View {
        Image("general/closeSmall")
            .resizable()
            .frame(width: 16, height: 16)
            .frame(width: buttonSize, height: buttonSize)
            .background(
                RoundedRectangle(cornerRadius: Islands.rowRadius, style: .continuous)
                    .fill(isHoveringClose || isPressingClose ? Islands.actionHover : Color.clear)
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged({ _ in
                        isPressingClose = true
                        closeButtonGestureActive = true
                    })
                    .onEnded({ value in
                        if value.location.x > 0
                            && value.location.x < buttonSize
                            && value.location.y > 0
                            && value.location.y < buttonSize {
                            closeAction()
                        }
                        isPressingClose = false
                        closeButtonGestureActive = false
                    })
            )
            .onHover { hover in
                isHoveringClose = hover
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(Text("Close"))
    }
}
