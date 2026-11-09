import SwiftUI

struct RecentLocationsRowView: View {
    let row: RecentLocationsRow
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            titleLine
            previewBlock
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Islands.rowRadius).fill(backgroundColor))
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onOpen)
        .onTapGesture(perform: onSelect)
        .onHover(perform: setHovering)
    }

    private var titleLine: some View {
        HStack(spacing: 6) {
            Image(row.fileIconName)
                .resizable()
                .interpolation(.high)
                .frame(width: 16, height: 16)
            Text(row.title)
                .font(Islands.smallFont.weight(.semibold))
                .foregroundStyle(Islands.foreground)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 8)
            if !row.relativeDirectory.isEmpty {
                Text(row.relativeDirectory)
                    .font(Islands.smallFont)
                    .foregroundStyle(Islands.disabledForeground)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        }
    }

    @ViewBuilder
    private var previewBlock: some View {
        switch row.preview {
        case .pending:
            EmptyView()
        case .emptyFile:
            Text(RecentLocationsViewModel.emptyFileText)
                .font(.custom(Islands.codeFontName, size: 12))
                .foregroundStyle(Islands.secondaryForeground)
        case .lines(let lines):
            VStack(alignment: .leading, spacing: 0) {
                ForEach(lines, id: \.number) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(line.number)")
                            .font(.custom(Islands.codeFontName, size: 11))
                            .foregroundStyle(line.isCaretLine ? Islands.lineNumberCaretRow : Islands.lineNumber)
                            .frame(minWidth: 28, alignment: .trailing)
                        Text(line.text.isEmpty ? " " : line.text)
                            .font(.custom(Islands.codeFontName, size: 12))
                            .foregroundStyle(Islands.editorForeground)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .padding(.vertical, 1)
                    .background(line.isCaretLine ? Islands.caretRow : Color.clear)
                }
            }
        }
    }

    func setHovering(_ hovering: Bool) {
        isHovering = hovering
    }

    private var backgroundColor: Color {
        Self.backgroundColor(isSelected: isSelected, isHovering: isHovering)
    }

    static func backgroundColor(isSelected: Bool, isHovering: Bool) -> Color {
        if isSelected {
            return Islands.selection
        }
        return isHovering ? Islands.hover : .clear
    }
}

struct RecentLocationsView: View {
    @Bindable var model: RecentLocationsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle()
                .fill(Islands.separator)
                .frame(height: 1)
            if model.rows.isEmpty {
                Text(RecentLocationsViewModel.emptyText)
                    .font(Islands.uiFont)
                    .foregroundStyle(Islands.secondaryForeground)
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
            Text(model.title)
                .font(Islands.headerTitleFont)
                .foregroundStyle(Islands.foreground)
                .lineLimit(1)
            Text(model.countText)
                .font(Islands.smallFont)
                .foregroundStyle(Islands.secondaryForeground)
                .lineLimit(1)
            Spacer(minLength: 8)
            Toggle(isOn: $model.showChangedOnly) {
                HStack(spacing: 4) {
                    Text(RecentLocationsViewModel.toggleTitle)
                        .font(Islands.smallFont)
                        .foregroundStyle(Islands.foreground)
                    Text(RecentLocationsViewModel.toggleShortcut)
                        .font(Islands.smallFont)
                        .foregroundStyle(Islands.secondaryForeground)
                }
            }
            .toggleStyle(.checkbox)
        }
        .padding(.horizontal, 10)
        .frame(height: Islands.popupHeaderHeight)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                        RecentLocationsRowView(
                            row: row,
                            isSelected: index == model.selectedIndex,
                            onSelect: selectAction(index),
                            onOpen: openAction(index)
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

    func selectAction(_ index: Int) -> () -> Void {
        { model.select(index) }
    }

    func openAction(_ index: Int) -> () -> Void {
        { model.open(index) }
    }
}
