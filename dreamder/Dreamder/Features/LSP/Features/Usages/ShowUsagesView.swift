import SwiftUI

struct ShowUsagesView: View {
    let model: ShowUsagesViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle()
                .fill(Islands.separator)
                .frame(height: 1)
            if let message = model.message {
                Text(message)
                    .font(Islands.uiFont)
                    .foregroundStyle(Islands.secondaryForeground)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassPopup()
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(model.headerTitle)
                .font(Islands.headerTitleFont)
                .foregroundStyle(Islands.foreground)
                .lineLimit(1)
            Spacer(minLength: 8)
            if !model.isMessage {
                Text(model.countText)
                    .font(Islands.smallFont)
                    .foregroundStyle(Islands.secondaryForeground)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: Islands.popupHeaderHeight)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                        ShowUsagesRowView(
                            row: row,
                            isSelected: index == model.selectedIndex,
                            onSelect: {
                                model.select(index)
                            },
                            onOpen: {
                                model.select(index)
                                model.activate()
                            }
                        )
                        .id(row.id)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
            }
            .onChange(of: model.selectedIndex) { _, _ in
                guard let id = model.selectedRow?.id else { return }
                proxy.scrollTo(id, anchor: .center)
            }
        }
    }
}
