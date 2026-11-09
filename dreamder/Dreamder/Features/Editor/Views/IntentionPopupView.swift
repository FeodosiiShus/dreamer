import SwiftUI

struct IntentionPopupView: View {
    let model: IntentionPopupModel

    var body: some View {
        Group {
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

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                        rowView(row, at: index)
                            .id(row.id)
                    }
                }
                .padding(.horizontal, IntentionPopupModel.listPadding)
                .padding(.vertical, IntentionPopupModel.listPadding)
            }
            .onChange(of: model.selectedIndex) {
                proxy.scrollTo(model.selectedRowID, anchor: .center)
            }
        }
    }

    @ViewBuilder
    private func rowView(_ row: IntentionPopupRow, at index: Int) -> some View {
        switch row {
        case .header(_, let title):
            IntentionPopupHeaderView(title: title)
        case .action(let action):
            IntentionPopupActionView(model: model, action: action, index: index)
        }
    }
}

struct IntentionPopupHeaderView: View {
    let title: String

    var body: some View {
        Text(title)
            .font(Islands.smallFont)
            .foregroundStyle(Islands.secondaryForeground)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: IntentionPopupModel.headerRowHeight)
    }
}

struct IntentionPopupActionView: View {
    let model: IntentionPopupModel
    let action: IntentionAction
    let index: Int

    var body: some View {
        HStack(spacing: 6) {
            icon
                .frame(width: 16, height: 16)
            Text(action.title)
                .font(Islands.uiFont)
                .foregroundStyle(Islands.foreground)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .frame(height: IntentionPopupModel.actionRowHeight)
        .background(
            RoundedRectangle(cornerRadius: Islands.rowRadius)
                .fill(model.selectedIndex == index ? Islands.selection : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: handleTap)
        .onHover(perform: handleHover)
    }

    func handleTap() {
        model.select(index)
        model.activate()
    }

    func handleHover(_ hovering: Bool) {
        if hovering {
            model.select(index)
        }
    }

    @ViewBuilder
    private var icon: some View {
        if let name = action.category.bulbIconName {
            Image(name)
                .resizable()
                .interpolation(.high)
        } else {
            Color.clear
        }
    }
}
