//
//  EditorTabCloseButton.swift
//  Dreamder
//
//  Created by Austin Condiff on 1/17/23.
//

import SwiftUI

@MainActor
@Observable
final class EditorTabClosePressModel {
    static let buttonSize: CGFloat = 16

    private(set) var isPressing = false

    static func isInsideButton(_ location: CGPoint) -> Bool {
        location.x > 0 && location.x < buttonSize && location.y > 0 && location.y < buttonSize
    }

    func began(active: Binding<Bool>) {
        isPressing = true
        active.wrappedValue = true
    }

    func ended(at location: CGPoint, active: Binding<Bool>, close: () -> Void) {
        if Self.isInsideButton(location) {
            close()
        }
        isPressing = false
        active.wrappedValue = false
    }
}

nonisolated protocol PointerLocated {
    var location: CGPoint { get }
}

extension DragGesture.Value: PointerLocated {}

struct EditorTabCloseButton: View {
    var closeAction: () -> Void
    @Binding var closeButtonGestureActive: Bool
    @Binding var isHoveringClose: Bool

    @State private var press = EditorTabClosePressModel()

    var body: some View {
        Image("general/closeSmall")
            .resizable()
            .frame(width: 16, height: 16)
            .frame(width: EditorTabClosePressModel.buttonSize, height: EditorTabClosePressModel.buttonSize)
            .background {
                if isHoveringClose || press.isPressing {
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
                    .onChanged(pressBegan)
                    .onEnded(pressEnded)
            )
            .onHover(perform: hoverChanged)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(Text("Close"))
    }

    func pressBegan(_ value: some PointerLocated) {
        press.began(active: $closeButtonGestureActive)
    }

    func pressEnded(_ value: some PointerLocated) {
        press.ended(at: value.location, active: $closeButtonGestureActive, close: closeAction)
    }

    func hoverChanged(_ hovering: Bool) {
        isHoveringClose = hovering
    }
}

struct EditorTabPinButton: View {
    var unpinAction: () -> Void
    @Binding var isHoveringClose: Bool

    var body: some View {
        Image(isHoveringClose ? "general/pinHovered" : "general/pin")
            .resizable()
            .frame(width: 16, height: 16)
            .contentShape(Rectangle())
            .onTapGesture(perform: unpinAction)
            .onHover(perform: hoverChanged)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(Text("Unpin Tab"))
    }

    func hoverChanged(_ hovering: Bool) {
        isHoveringClose = hovering
    }
}
