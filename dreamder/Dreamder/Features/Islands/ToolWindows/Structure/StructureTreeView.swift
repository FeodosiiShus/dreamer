import SwiftUI

struct StructureToggleButton: View {
    let icon: String
    let help: String
    let isOn: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(icon)
                .resizable()
                .frame(width: 16, height: 16)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: Islands.controlRadius)
                        .fill(background)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover(perform: setHovering)
        .accessibilityIdentifier("StructureToggle.\(help)")
        .accessibilityValue(isOn ? "on" : "off")
    }

    func setHovering(_ hovering: Bool) {
        isHovering = hovering
    }

    private var background: Color {
        if isOn {
            return Islands.selection
        }
        return isHovering ? Islands.actionHover : .clear
    }
}

struct StructureFilterField: View {
    @Bindable var model: StructureViewModel
    let workspace: WorkspaceDocument
    var onSubmit: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        IslandSearchField("Filter symbols", text: $model.filterText, focus: $isFocused, onSubmit: onSubmit)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .onKeyPress(.downArrow, action: moveDown)
            .onKeyPress(.upArrow, action: moveUp)
            .accessibilityIdentifier("StructureFilterField")
    }

    func moveDown() -> KeyPress.Result {
        move(1)
    }

    func moveUp() -> KeyPress.Result {
        move(-1)
    }

    func move(_ delta: Int) -> KeyPress.Result {
        model.moveSelection(by: delta, workspace: workspace)
        return .handled
    }
}

struct StructureTreeView: View {
    let model: StructureViewModel
    let workspace: WorkspaceDocument
    var activatesOnClick = false
    var onActivate: () -> Void = {}

    @FocusState private var isFocused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(model.rows) { row in
                        symbolRow(row)
                    }
                }
                .padding(.vertical, 2)
            }
            .onChange(of: model.scrollRequests) {
                if let target = model.scrollTarget {
                    proxy.scrollTo(target, anchor: .center)
                }
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onKeyPress(.return, action: returnPressed)
        .onKeyPress(.downArrow, action: moveDown)
        .onKeyPress(.upArrow, action: moveUp)
        .onChange(of: model.focusRequests) { isFocused = true }
    }

    func returnPressed() -> KeyPress.Result {
        let result = model.activateSelection(workspace: workspace)
        onActivate()
        return result
    }

    func clicked(_ node: StructureNode) {
        if activatesOnClick {
            doubleClicked(node)
        } else {
            model.select(node, workspace: workspace)
        }
    }

    func doubleClicked(_ node: StructureNode) {
        model.activate(node, workspace: workspace)
        if !node.isGroup {
            onActivate()
        }
    }

    func moveDown() -> KeyPress.Result {
        move(1)
    }

    func moveUp() -> KeyPress.Result {
        move(-1)
    }

    func move(_ delta: Int) -> KeyPress.Result {
        model.moveSelection(by: delta, workspace: workspace)
        return .handled
    }

    private func symbolRow(_ row: StructureRow) -> some View {
        let node = row.node
        let isCollapsed = model.collapsed.contains(node.id) && !model.isFiltering
        let isSelected = model.selection == node.id
        return HStack(spacing: 5) {
            if node.children.isEmpty {
                Color.clear
                    .frame(width: 12, height: 12)
            } else {
                Image(isCollapsed ? "general/chevronRight" : "general/chevronDown")
                    .resizable()
                    .frame(width: 12, height: 12)
                    .opacity(0.7)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: bound(model.toggleCollapsed, node.id))
            }
            Image(node.isGroup ? "nodes/package" : node.kind.iconName)
                .resizable()
                .frame(width: 16, height: 16)
            Text(node.name)
                .font(Islands.uiFont)
                .foregroundStyle(Islands.foreground)
                .lineLimit(1)
            if let detail = node.detail, !detail.isEmpty {
                Text(node.isGroup ? "(\(detail))" : detail)
                    .font(Islands.smallFont)
                    .foregroundStyle(Islands.secondaryForeground)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 4)
            if !node.isGroup {
                Text("\(node.line)")
                    .font(Islands.smallFont)
                    .foregroundStyle(Islands.disabledForeground)
            }
        }
        .padding(.leading, CGFloat(8 + row.depth * 14))
        .padding(.trailing, 8)
        .frame(height: Islands.listRowHeight)
        .background(
            RoundedRectangle(cornerRadius: Islands.rowRadius)
                .fill(isSelected ? Islands.selection : Color.clear)
                .padding(.horizontal, 4)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: bound(doubleClicked, node))
        .onTapGesture(perform: bound(clicked, node))
    }
}
