import SwiftUI

struct SelectableRowList<Item: Identifiable & Hashable, Content: View>: View {
    let data: [Item]
    let rowHeight: CGFloat
    @Binding var selection: Item?
    let onActivate: () -> Void
    let itemView: (Item) -> Content

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(data) { item in
                        rowView(for: item)
                            .id(item.id)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
            }
            .onChange(of: selection, initial: true) {
                scrollToSelection(using: proxy)
            }
            .onChange(of: data) {
                scrollToSelection(using: proxy)
            }
        }
    }

    func rowView(for item: Item) -> SelectableRow<Content> {
        SelectableRow(
            height: rowHeight,
            isSelected: item == selection,
            onSelect: {
                selection = item
            },
            onActivate: {
                selection = item
                onActivate()
            },
            content: itemView(item)
        )
    }

    func scrollToSelection(using proxy: ScrollViewProxy) {
        guard let selection, data.contains(selection) else { return }
        proxy.scrollTo(selection.id)
    }
}

struct SelectableRow<Content: View>: View {
    let height: CGFloat
    let isSelected: Bool
    let onSelect: () -> Void
    let onActivate: () -> Void
    let content: Content

    @State private var isHovering = false

    var body: some View {
        content
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: Islands.rowRadius)
                    .fill(Self.backgroundColor(isSelected: isSelected, isHovering: isHovering))
            )
            .contentShape(Rectangle())
            .onTapGesture(count: 2, perform: onActivate)
            .onTapGesture(perform: onSelect)
            .onHover(perform: hoverChanged)
    }

    func hoverChanged(_ hovering: Bool) {
        isHovering = hovering
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
