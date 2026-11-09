import SwiftUI

@MainActor
@Observable
final class MarkdownTableGridSelection {
    private(set) var grid = MarkdownTableGridModel()

    func select(row: Int, column: Int) {
        grid.select(row: row, column: column)
    }

    func move(rowDelta: Int, columnDelta: Int) {
        grid.move(rowDelta: rowDelta, columnDelta: columnDelta)
    }
}

struct MarkdownTableGridPicker: View {
    static let cellSize: CGFloat = 15
    static let cellSpacing: CGFloat = 3

    let onSelect: (_ contentRows: Int, _ columns: Int) -> Void

    @State private var selection: MarkdownTableGridSelection
    @FocusState private var isFocused: Bool

    init(
        selection: MarkdownTableGridSelection = MarkdownTableGridSelection(),
        onSelect: @escaping (_ contentRows: Int, _ columns: Int) -> Void
    ) {
        self.onSelect = onSelect
        _selection = State(initialValue: selection)
    }

    private var step: CGFloat { Self.cellSize + Self.cellSpacing }

    var body: some View {
        VStack(spacing: 8) {
            grid
            Text(selection.grid.label)
                .font(Islands.smallFont)
                .foregroundStyle(Islands.secondaryForeground)
        }
        .padding(8)
        .background(Islands.popup)
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onAppear(perform: focus)
        .onKeyPress(.rightArrow, action: moveRight)
        .onKeyPress(.leftArrow, action: moveLeft)
        .onKeyPress(.upArrow, action: moveUp)
        .onKeyPress(.downArrow, action: moveDown)
        .onKeyPress(.return, action: confirmFromKeyboard)
    }

    private var grid: some View {
        VStack(spacing: Self.cellSpacing) {
            ForEach(0..<selection.grid.rows, id: \.self) { row in
                HStack(spacing: Self.cellSpacing) {
                    ForEach(0..<selection.grid.columns, id: \.self) { column in
                        cell(row: row, column: column)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onContinuousHover(perform: hover)
        .onTapGesture(coordinateSpace: .local, perform: tap(at:))
    }

    private func cell(row: Int, column: Int) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(selection.grid.isHighlighted(row: row, column: column) ? Islands.selection : Islands.islandRaised)
            .overlay(RoundedRectangle(cornerRadius: 2).stroke(Islands.componentBorder, lineWidth: 1))
            .frame(width: Self.cellSize, height: Self.cellSize)
    }

    private func focus() {
        isFocused = true
    }

    func hover(_ phase: HoverPhase) {
        if case .active(let location) = phase {
            select(at: location)
        }
    }

    func tap(at location: CGPoint) {
        select(at: location)
        confirm()
    }

    func moveRight() -> KeyPress.Result {
        move(0, 1)
    }

    func moveLeft() -> KeyPress.Result {
        move(0, -1)
    }

    func moveUp() -> KeyPress.Result {
        move(-1, 0)
    }

    func moveDown() -> KeyPress.Result {
        move(1, 0)
    }

    func confirmFromKeyboard() -> KeyPress.Result {
        confirm()
        return .handled
    }

    private func select(at location: CGPoint) {
        selection.select(row: Int(location.y / step), column: Int(location.x / step))
    }

    private func move(_ rowDelta: Int, _ columnDelta: Int) -> KeyPress.Result {
        selection.move(rowDelta: rowDelta, columnDelta: columnDelta)
        return .handled
    }

    private func confirm() {
        onSelect(selection.grid.contentRows, selection.grid.tableColumns)
    }
}
