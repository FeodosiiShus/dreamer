import SwiftUI

struct MarkdownPreviewLayoutButtons: View {
    let store: MarkdownPreviewLayoutStore
    let url: URL

    @State private var hovered: MarkdownPreviewLayout?

    var body: some View {
        let selected = store.layout(for: url)
        let isVerticalSplit = store.isVerticalSplit(for: url)
        HStack(spacing: 2) {
            ForEach(MarkdownPreviewLayout.allCases) { mode in
                button(for: mode, selected: selected, isVerticalSplit: isVerticalSplit)
            }
        }
        .accessibilityIdentifier("MarkdownPreviewLayoutButtons")
    }

    private func button(
        for mode: MarkdownPreviewLayout,
        selected: MarkdownPreviewLayout,
        isVerticalSplit: Bool
    ) -> some View {
        Button {
            store.select(mode, for: url)
        } label: {
            mode.icon(isVerticalSplit: isVerticalSplit)
                .resizable()
                .interpolation(.high)
                .frame(width: 16, height: 16)
                .frame(width: 24, height: Islands.tabPillHeight)
                .background(
                    RoundedRectangle(cornerRadius: Islands.rowRadius, style: .continuous)
                        .fill(background(for: mode, selected: selected))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(mode.title)
        .accessibilityLabel(mode.title)
        .onHover { hovering in
            if hovering {
                hovered = mode
            } else if hovered == mode {
                hovered = nil
            }
        }
    }

    private func background(for mode: MarkdownPreviewLayout, selected: MarkdownPreviewLayout) -> Color {
        if mode == selected {
            return Islands.selection
        }
        if mode == hovered {
            return Islands.actionHover
        }
        return .clear
    }
}
