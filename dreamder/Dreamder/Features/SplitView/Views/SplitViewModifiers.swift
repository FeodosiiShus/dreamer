//
//  SplitViewModifiers.swift
//  Dreamder
//
//  Created by Wouter Hennen on 05/03/2023.
//

import SwiftUI

extension ContainerValues {
    @Entry var splitPaneCollapsed: Bool = false
    @Entry var splitPaneCanCollapse: Bool = false
    @Entry var splitPaneHoldingPriority: Float = SplitLayoutPane.defaultHoldingPriority
    @Entry var splitPaneMinLength: CGFloat = 0
    @Entry var splitPaneMaxLength: CGFloat = .infinity
}

nonisolated enum SplitLayoutRole: Sendable {
    case pane
    case divider
}

nonisolated struct SplitLayoutRoleKey: LayoutValueKey {
    static let defaultValue = SplitLayoutRole.pane
}

nonisolated struct SplitLayoutCollapsedKey: LayoutValueKey {
    static let defaultValue = false
}

nonisolated struct SplitLayoutHoldingPriorityKey: LayoutValueKey {
    static let defaultValue = SplitLayoutPane.defaultHoldingPriority
}

nonisolated struct SplitLayoutMinLengthKey: LayoutValueKey {
    static let defaultValue: CGFloat = 0
}

nonisolated struct SplitLayoutMaxLengthKey: LayoutValueKey {
    static let defaultValue: CGFloat = .infinity
}

extension View {
    func collapsed(_ value: Binding<Bool>) -> some View {
        containerValue(\.splitPaneCollapsed, value.wrappedValue)
    }

    func collapsable() -> some View {
        containerValue(\.splitPaneCanCollapse, true)
    }

    func holdingPriority(_ priority: NSLayoutConstraint.Priority) -> some View {
        containerValue(\.splitPaneHoldingPriority, priority.rawValue)
    }

    func splitPaneMinLength(_ points: CGFloat) -> some View {
        containerValue(\.splitPaneMinLength, points)
    }

    func splitPaneMaxLength(_ points: CGFloat) -> some View {
        containerValue(\.splitPaneMaxLength, points)
    }
}
