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
            .background {
                if isHoveringClose || isPressingClose {
                    Capsule()
                        .fill(Islands.tabHoverFill)
                        .overlay {
                            Capsule().strokeBorder(Islands.glassBorder, lineWidth: 1)
                        }
                }
            }
            .contentShape(Capsule())
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
