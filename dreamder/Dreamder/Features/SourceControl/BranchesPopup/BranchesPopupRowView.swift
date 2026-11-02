import SwiftUI

struct BranchesPopupRowView: View {
    let row: BranchesPopupRow
    let isSelected: Bool
    let isExpanded: Bool
    let onActivate: () -> Void
    let onToggle: () -> Void
    let onOpenMenu: () -> Void
    let onToggleFavorite: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            disclosure
            if let iconName = row.iconName {
                Image(iconName)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 16, height: 16)
            }
            titleText
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            if let counters = row.counters {
                Text(counters)
                    .font(Islands.smallFont)
                    .foregroundStyle(Islands.secondaryForeground)
                    .lineLimit(1)
            }
            if let detail = row.detail {
                Text(detail)
                    .font(Islands.smallFont)
                    .foregroundStyle(Islands.secondaryForeground)
                    .lineLimit(1)
            }
            if let shortcut = row.shortcut {
                Text(shortcut)
                    .font(Islands.smallFont)
                    .foregroundStyle(Islands.secondaryForeground)
            }
            if row.kind == .ref {
                if row.isFavorite || isHovering {
                    Button {
                        onToggleFavorite()
                    } label: {
                        Image(row.isFavorite ? "nodes/star" : "nodes/starEmpty")
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 14, height: 14)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(row.isFavorite ? "Remove from Favorites" : "Add to Favorites")
                }
                Button {
                    onOpenMenu()
                } label: {
                    Image("general/chevronRight")
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 12, height: 12)
                        .padding(.leading, 2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 6 + CGFloat(row.depth) * 14)
        .padding(.trailing, 6)
        .frame(height: Islands.treeRowHeight)
        .background(
            RoundedRectangle(cornerRadius: Islands.rowRadius)
                .fill(backgroundColor)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            switch row.kind {
            case .section, .group:
                onToggle()
            case .separator:
                break
            default:
                onActivate()
            }
        }
        .onHover { isHovering = $0 }
    }

    private var titleText: Text {
        guard !row.matchRanges.isEmpty else {
            return Text(row.title)
                .font(Islands.uiFont)
                .foregroundColor(Islands.foreground)
        }
        let characters = Array(row.title)
        let highlighted = Set(row.matchRanges.flatMap { Array($0) })
        var result = Text("")
        var buffer = ""
        var bufferHighlighted = false
        func flush() {
            guard !buffer.isEmpty else { return }
            var text = Text(buffer).font(Islands.uiFont)
            text = text.foregroundColor(bufferHighlighted ? Islands.searchMatch : Islands.foreground)
            result = result + text
            buffer = ""
        }
        for (index, character) in characters.enumerated() {
            let isHighlighted = highlighted.contains(index)
            if isHighlighted != bufferHighlighted {
                flush()
                bufferHighlighted = isHighlighted
            }
            buffer.append(character)
        }
        flush()
        return result
    }

    @ViewBuilder
    private var disclosure: some View {
        if row.kind == .section || row.kind == .group {
            Image(isExpanded ? "general/chevronDown" : "general/chevronRight")
                .resizable()
                .interpolation(.high)
                .frame(width: 12, height: 12)
                .foregroundStyle(Islands.secondaryForeground)
        } else if row.depth > 0 {
            Color.clear.frame(width: 12, height: 12)
        }
    }

    private var backgroundColor: Color {
        if isSelected {
            return Islands.selection
        }
        if isHovering {
            return Islands.hover
        }
        return .clear
    }
}
