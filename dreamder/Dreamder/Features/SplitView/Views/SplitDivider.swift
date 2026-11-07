import SwiftUI

struct SplitDivider: View {
    static let hitThickness: CGFloat = 7
    static let nudgeStep: CGFloat = 10
    static let largeNudgeStep: CGFloat = 50

    let axis: Axis
    let style: DreamderDividerStyle
    let onDrag: (CGFloat) -> Void
    let onDragEnd: () -> Void
    let onNudge: (CGFloat) -> Void
    let onEqualize: () -> Void

    private var isRow: Bool { axis == .horizontal }

    var body: some View {
        Rectangle()
            .fill(style.color)
            .frame(width: isRow ? style.thickness : nil, height: isRow ? nil : style.thickness)
            .frame(
                maxWidth: isRow ? Self.hitThickness : .infinity,
                maxHeight: isRow ? .infinity : Self.hitThickness
            )
            .contentShape(Rectangle())
            .pointerStyle(isRow ? PointerStyle.columnResize : PointerStyle.rowResize)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        onDrag(isRow ? value.translation.width : value.translation.height)
                    }
                    .onEnded { _ in onDragEnd() }
            )
            .simultaneousGesture(TapGesture(count: 2).onEnded { onEqualize() })
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow], phases: [.down, .repeat]) { press in
                handleKey(press)
            }
            .accessibilityElement()
            .accessibilityLabel("Split divider")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    onNudge(Self.nudgeStep)
                case .decrement:
                    onNudge(-Self.nudgeStep)
                @unknown default:
                    break
                }
            }
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        let step = press.modifiers.contains(.shift) ? Self.largeNudgeStep : Self.nudgeStep
        switch (isRow, press.key) {
        case (true, .leftArrow), (false, .upArrow):
            onNudge(-step)
            return .handled
        case (true, .rightArrow), (false, .downArrow):
            onNudge(step)
            return .handled
        default:
            return .ignored
        }
    }
}
