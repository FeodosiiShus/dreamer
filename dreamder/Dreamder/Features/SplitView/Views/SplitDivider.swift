import SwiftUI

struct SplitDivider: View {
    static let hitThickness: CGFloat = 7
    static let nudgeStep: CGFloat = 10
    static let largeNudgeStep: CGFloat = 50
    static let arrowKeys: Set<KeyEquivalent> = [.leftArrow, .rightArrow, .upArrow, .downArrow]

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
                    .onChanged(reading(\.translation, into: drag))
                    .onEnded(discarding(onDragEnd))
            )
            .simultaneousGesture(TapGesture(count: 2).onEnded(discarding(onEqualize)))
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(keys: Self.arrowKeys, phases: [.down, .repeat], action: reading(\.key, \.modifiers, into: handleKey))
            .accessibilityElement()
            .accessibilityLabel("Split divider")
            .accessibilityAdjustableAction(adjust)
    }

    func drag(_ translation: CGSize) {
        onDrag(isRow ? translation.width : translation.height)
    }

    func handleKey(_ key: KeyEquivalent, _ modifiers: EventModifiers) -> KeyPress.Result {
        let step = modifiers.contains(.shift) ? Self.largeNudgeStep : Self.nudgeStep
        switch (isRow, key) {
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

    func adjust(_ direction: AccessibilityAdjustmentDirection) {
        _ = Self.adjustmentDelta(direction).map(onNudge)
    }

    static func adjustmentDelta(_ direction: AccessibilityAdjustmentDirection) -> CGFloat? {
        direction == .increment ? nudgeStep : (direction == .decrement ? -nudgeStep : nil)
    }
}
