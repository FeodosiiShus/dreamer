import SwiftUI

struct ShowUsagesRowView: View {
    let row: LSPUsageRow
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Image(row.fileIconName)
                .resizable()
                .interpolation(.high)
                .frame(width: 16, height: 16)
            Text("\(row.fileName):\(row.displayLine)")
                .font(Islands.smallFont)
                .foregroundStyle(Islands.secondaryForeground)
                .lineLimit(1)
                .fixedSize()
            codeLine
            Spacer(minLength: 8)
            if !row.relativeDirectory.isEmpty {
                Text(row.relativeDirectory)
                    .font(Islands.smallFont)
                    .foregroundStyle(Islands.disabledForeground)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 6)
        .frame(height: Self.rowHeight(isCompact: Islands.isCompact))
        .background(
            RoundedRectangle(cornerRadius: Islands.rowRadius)
                .fill(Self.backgroundColor(isSelected: isSelected, isHovering: isHovering))
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onOpen)
        .onTapGesture(perform: onSelect)
        .onHover(perform: hoverChanged)
    }

    func hoverChanged(_ hovering: Bool) {
        isHovering = hovering
    }

    static func rowHeight(isCompact: Bool) -> CGFloat {
        isCompact ? 22 : 24
    }

    private var codeLine: some View {
        Text(highlightedLine)
            .font(.custom(Islands.codeFontName, size: 12))
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private var highlightedLine: AttributedString {
        let text = row.lineText
        let length = (text as NSString).length
        guard let matchRange = row.matchRange,
              matchRange.location >= 0,
              matchRange.location + matchRange.length <= length else {
            var whole = AttributedString(text)
            whole.foregroundColor = Islands.editorForeground
            return whole
        }

        let string = text as NSString
        var result = AttributedString()

        var prefix = AttributedString(string.substring(to: matchRange.location))
        prefix.foregroundColor = Islands.editorForeground
        result.append(prefix)

        var match = AttributedString(string.substring(with: matchRange))
        match.foregroundColor = Islands.searchMatch
        match.backgroundColor = Islands.searchMatch.opacity(0.2)
        result.append(match)

        var suffix = AttributedString(string.substring(from: matchRange.location + matchRange.length))
        suffix.foregroundColor = Islands.editorForeground
        result.append(suffix)

        return result
    }

    static func backgroundColor(isSelected: Bool, isHovering: Bool) -> Color {
        if isSelected {
            return Islands.selection
        }
        if isHovering {
            return Islands.hover
        }
        return .clear
    }
}
