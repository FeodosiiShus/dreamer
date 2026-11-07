import SwiftUI

struct MarkdownTableGridPicker: View {
    static let cellSize: CGFloat = 15
    static let cellSpacing: CGFloat = 3

    let onSelect: (_ contentRows: Int, _ columns: Int) -> Void

    @State private var model = MarkdownTableGridModel()
    @FocusState private var isFocused: Bool

    private var step: CGFloat { Self.cellSize + Self.cellSpacing }

    var body: some View {
        VStack(spacing: 8) {
            grid
            Text(model.label)
                .font(Islands.smallFont)
                .foregroundStyle(Islands.secondaryForeground)
        }
        .padding(8)
        .background(Islands.popup)
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onAppear { isFocused = true }
        .onKeyPress(.rightArrow) { move(0, 1) }
        .onKeyPress(.leftArrow) { move(0, -1) }
        .onKeyPress(.upArrow) { move(-1, 0) }
        .onKeyPress(.downArrow) { move(1, 0) }
        .onKeyPress(.return) {
            confirm()
            return .handled
        }
    }

    private var grid: some View {
        VStack(spacing: Self.cellSpacing) {
            ForEach(0..<model.rows, id: \.self) { row in
                HStack(spacing: Self.cellSpacing) {
                    ForEach(0..<model.columns, id: \.self) { column in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(
                                model.isHighlighted(row: row, column: column)
                                    ? Islands.selection
                                    : Islands.islandRaised
                            )
                            .overlay(RoundedRectangle(cornerRadius: 2).stroke(Islands.componentBorder, lineWidth: 1))
                            .frame(width: Self.cellSize, height: Self.cellSize)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            if case .active(let location) = phase {
                model.select(row: Int(location.y / step), column: Int(location.x / step))
            }
        }
        .onTapGesture { location in
            model.select(row: Int(location.y / step), column: Int(location.x / step))
            confirm()
        }
    }

    private func move(_ rowDelta: Int, _ columnDelta: Int) -> KeyPress.Result {
        model.move(rowDelta: rowDelta, columnDelta: columnDelta)
        return .handled
    }

    private func confirm() {
        onSelect(model.contentRows, model.tableColumns)
    }
}
