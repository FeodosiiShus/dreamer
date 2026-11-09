import SwiftUI

@Observable
final class MarkdownPreviewLayoutHover {
    private(set) var hovered: MarkdownPreviewLayout?

    func update(_ mode: MarkdownPreviewLayout, isHovering: Bool) {
        if isHovering {
            hovered = mode
        } else if hovered == mode {
            hovered = nil
        }
    }
}

struct MarkdownPreviewLayoutButtons: View {
    let store: MarkdownPreviewLayoutStore
    let url: URL

    @State private var hover: MarkdownPreviewLayoutHover

    init(
        store: MarkdownPreviewLayoutStore,
        url: URL,
        hover: MarkdownPreviewLayoutHover = MarkdownPreviewLayoutHover()
    ) {
        self.store = store
        self.url = url
        self._hover = State(initialValue: hover)
    }

    static func selectionAction(
        for mode: MarkdownPreviewLayout,
        store: MarkdownPreviewLayoutStore,
        url: URL
    ) -> () -> Void {
        { store.select(mode, for: url) }
    }

    static func hoverAction(for mode: MarkdownPreviewLayout, hover: MarkdownPreviewLayoutHover) -> (Bool) -> Void {
        { isHovering in hover.update(mode, isHovering: isHovering) }
    }

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
        Button(action: Self.selectionAction(for: mode, store: store, url: url)) {
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
        .onHover(perform: Self.hoverAction(for: mode, hover: hover))
    }

    private func background(for mode: MarkdownPreviewLayout, selected: MarkdownPreviewLayout) -> Color {
        if mode == selected {
            return Islands.selection
        }
        if mode == hover.hovered {
            return Islands.actionHover
        }
        return .clear
    }
}
