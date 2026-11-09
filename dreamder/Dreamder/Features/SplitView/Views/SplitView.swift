//
//  SplitView.swift
//  Dreamder
//
//  Created by Wouter Hennen on 22/02/2023.
//

import SwiftUI

struct SplitView<Content: View>: View {
    var axis: Axis
    var dividerStyle: DreamderDividerStyle
    var weights: Binding<[CGFloat]>?
    var content: Content

    init(
        axis: Axis,
        dividerStyle: DreamderDividerStyle = .system(.thin),
        weights: Binding<[CGFloat]>? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.axis = axis
        self.dividerStyle = dividerStyle
        self.weights = weights
        self.content = content()
    }

    var body: some View {
        Group(subviews: content) { subviews in
            SplitPanes(axis: axis, dividerStyle: dividerStyle, weights: weights, subviews: subviews)
        }
    }
}

private struct SplitPanes: View {
    let axis: Axis
    let dividerStyle: DreamderDividerStyle
    let weights: Binding<[CGFloat]>?
    let subviews: SubviewsCollection

    @State private var localWeights: [CGFloat] = []
    @State private var coordinator = SplitPaneCoordinator()

    private var sourceWeights: [CGFloat] {
        weights?.wrappedValue ?? localWeights
    }

    private var resolvedWeights: [CGFloat] {
        SplitLayoutMath.normalizedWeights(sourceWeights, count: subviews.count)
    }

    private var normalizationKey: Int {
        SplitLayoutMath.isValid(weights: sourceWeights, count: subviews.count) ? -1 : subviews.count
    }

    private func isCollapsed(_ subview: Subview) -> Bool {
        subview.containerValues.splitPaneCanCollapse && subview.containerValues.splitPaneCollapsed
    }

    private var dividerCount: Int {
        max(0, subviews.filter { !isCollapsed($0) }.count - 1)
    }

    var body: some View {
        let isRow = axis == .horizontal
        return SplitLayout(
            axis: axis,
            dividerThickness: dividerStyle.thickness,
            hitThickness: SplitDivider.hitThickness,
            weights: resolvedWeights,
            probe: coordinator.probe
        ) {
            ForEach(subviews) { subview in
                pane(subview)
            }
            ForEach(0..<dividerCount, id: \.self) { pair in
                divider(pair: pair)
            }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            isRow ? proxy.size.width : proxy.size.height
        } action: { oldLength, newLength in
            applyHoldingPriorities(from: oldLength, to: newLength)
        }
        .onChange(of: normalizationKey, initial: true) { _, key in
            if key >= 0 {
                commit(SplitLayoutMath.equalWeights(count: subviews.count))
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func pane(_ subview: Subview) -> some View {
        let collapsed = isCollapsed(subview)
        return subview
            .opacity(collapsed ? 0 : 1)
            .allowsHitTesting(!collapsed)
            .accessibilityHidden(collapsed)
            .layoutValue(key: SplitLayoutCollapsedKey.self, value: collapsed)
            .layoutValue(
                key: SplitLayoutHoldingPriorityKey.self,
                value: subview.containerValues.splitPaneHoldingPriority
            )
            .layoutValue(key: SplitLayoutMinLengthKey.self, value: subview.containerValues.splitPaneMinLength)
            .layoutValue(key: SplitLayoutMaxLengthKey.self, value: subview.containerValues.splitPaneMaxLength)
    }

    private func divider(pair: Int) -> some View {
        let actions = SplitDividerActions(
            pair: pair,
            paneCount: subviews.count,
            coordinator: $coordinator,
            commit: commit
        )
        return SplitDivider(
            axis: axis,
            style: dividerStyle,
            onDrag: actions.drag,
            onDragEnd: actions.endDrag,
            onNudge: actions.nudge,
            onEqualize: actions.equalize
        )
        .layoutValue(key: SplitLayoutRoleKey.self, value: .divider)
        .zIndex(1)
    }

    private func applyHoldingPriorities(from oldLength: CGFloat, to newLength: CGFloat) {
        let resized = coordinator.resized(from: oldLength, to: newLength, dividerThickness: dividerStyle.thickness)
        _ = resized.map(commit)
    }

    private func commit(_ newWeights: [CGFloat]) {
        _ = SplitPaneCoordinator.changed(newWeights, from: sourceWeights).map(store)
    }

    private func store(_ newWeights: [CGFloat]) {
        if let weights {
            weights.wrappedValue = newWeights
        } else {
            localWeights = newWeights
        }
    }
}
