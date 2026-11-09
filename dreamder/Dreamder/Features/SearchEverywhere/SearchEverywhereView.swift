import Foundation
import SwiftUI

struct SearchEverywhereView: View {
    @Bindable var model: SearchEverywhereViewModel

    @FocusState private var isQueryFocused: Bool

    init(model: SearchEverywhereViewModel) {
        self.model = model
    }

    var body: some View {
        VStack(spacing: 0) {
            if model.mode == .everywhere {
                tabRow
                divider
            }
            queryField
            divider
            results
            if model.mode == .everywhere, model.showsPreview, let preview = model.preview {
                divider
                SearchEverywherePreviewView(preview: preview)
            }
            divider
            footer
        }
        .frame(width: model.panelWidth, height: model.panelHeight)
        .glassPopup()
        .task {
            try? await Task.sleep(for: .milliseconds(50))
            isQueryFocused = true
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Islands.separator)
            .frame(height: 1)
    }

    private var tabRow: some View {
        HStack(spacing: 4) {
            ForEach(SearchEverywhereTab.allCases) { tab in
                SearchEverywhereTabButton(tab: tab, isSelected: model.tab == tab, onSelect: model.selectTab)
            }
            Spacer(minLength: 8)
            if model.isIndexing {
                Text("Indexing\u{2026}")
                    .font(Islands.smallFont)
                    .foregroundStyle(Islands.secondaryForeground)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: Islands.popupHeaderHeight)
    }

    private var queryField: some View {
        HStack(spacing: 8) {
            Image("general/search")
                .resizable()
                .frame(width: 16, height: 16)
            TextField(model.mode == .recentFiles ? "Search recent files" : "Search everywhere", text: $model.query)
                .textFieldStyle(.plain)
                .font(Islands.uiFont)
                .foregroundStyle(Islands.foreground)
                .focused($isQueryFocused)
                .defaultFocus($isQueryFocused, true)
                .onSubmit(model.openSelected)
        }
        .padding(.horizontal, 12)
        .frame(height: Islands.popupHeaderHeight)
    }

    private var results: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(model.sections) { section in
                        sectionHeader(section)
                        ForEach(section.items) { item in
                            SearchEverywhereRow(
                                item: item,
                                isSelected: model.selectedItem?.id == item.id,
                                onSelect: model.select,
                                onOpen: model.openSelected
                            )
                            .id(item.id)
                        }
                    }
                    if model.sections.isEmpty {
                        Text(emptyMessage)
                            .font(Islands.uiFont)
                            .foregroundStyle(Islands.secondaryForeground)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 12)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
            }
            .onChange(of: model.selection) { _, _ in
                guard let item = model.selectedItem else { return }
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo(item.id, anchor: .center)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyMessage: String {
        if model.mode == .recentFiles {
            return model.query.trimmingCharacters(in: .whitespaces).isEmpty
                ? "No recent files"
                : "No recent files match"
        }
        return model.query.trimmingCharacters(in: .whitespaces).isEmpty
            ? "Type to search files, classes, symbols, actions and text"
            : "No results"
    }

    private func sectionHeader(_ section: SearchEverywhereSection) -> some View {
        HStack(spacing: 8) {
            Text(section.kind.title)
                .font(Islands.smallFont)
                .foregroundStyle(Islands.secondaryForeground)
            Rectangle()
                .fill(Islands.separator)
                .frame(height: 1)
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if model.mode == .everywhere {
                footerHint("\u{21E5}", "Tabs")
            }
            footerHint("\u{2191}\u{2193}", "Navigate")
            footerHint("\u{23CE}", "Open")
            footerHint("\u{238B}", "Close")
            Spacer(minLength: 8)
            if model.mode == .everywhere {
                Button(action: model.togglePreview) {
                    HStack(spacing: 5) {
                        Image("general/previewOnly")
                            .resizable()
                            .frame(width: 14, height: 14)
                        Text("Preview")
                            .font(Islands.smallFont)
                            .foregroundStyle(model.showsPreview ? Islands.foreground : Islands.secondaryForeground)
                    }
                    .padding(.horizontal, 6)
                    .frame(height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: Islands.rowRadius)
                            .fill(model.showsPreview ? Islands.actionHover : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: Islands.popupFooterHeight)
    }

    private func footerHint(_ keys: String, _ title: String) -> some View {
        HStack(spacing: 4) {
            Text(keys)
                .font(Islands.smallFont)
                .foregroundStyle(Islands.disabledForeground)
            Text(title)
                .font(Islands.smallFont)
                .foregroundStyle(Islands.secondaryForeground)
        }
    }
}

struct SearchEverywhereRow: View {
    let item: SearchEverywhereItem
    let isSelected: Bool
    let onSelect: @MainActor (SearchEverywhereItem) -> Void
    let onOpen: @MainActor () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(item.iconName)
                .resizable()
                .frame(width: 16, height: 16)
            SearchEverywhereHighlightedText(text: item.title, ranges: item.ranges)
                .font(item.kind == .text ? Islands.codeFont : Islands.uiFont)
            Spacer(minLength: 8)
            if !item.detail.isEmpty {
                Text(item.detail)
                    .font(Islands.smallFont)
                    .foregroundStyle(Islands.secondaryForeground)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let shortcut = item.action?.shortcut, !shortcut.isEmpty {
                Text(shortcut)
                    .font(Islands.smallFont)
                    .foregroundStyle(Islands.secondaryForeground)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 8)
        .frame(height: Islands.popupRowHeight)
        .background(
            RoundedRectangle(cornerRadius: Islands.rowRadius)
                .fill(isSelected ? Islands.selection : (isHovering ? Islands.hover : Color.clear))
        )
        .contentShape(Rectangle())
        .onHover(perform: setHovering)
        .onTapGesture(perform: activate)
    }

    func setHovering(_ hovering: Bool) {
        isHovering = hovering
    }

    func activate() {
        onSelect(item)
        onOpen()
    }
}

struct SearchEverywhereTabButton: View {
    let tab: SearchEverywhereTab
    let isSelected: Bool
    let onSelect: @MainActor (SearchEverywhereTab) -> Void

    var body: some View {
        ToolWindowTab(title: tab.title, icon: nil, isSelected: isSelected, onClose: nil, action: select)
    }

    func select() {
        onSelect(tab)
    }
}

struct SearchEverywhereHighlightedText: View {
    let text: String
    let ranges: [NSRange]

    var body: some View {
        Text(attributedText)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    private var attributedText: AttributedString {
        var result = AttributedString()
        for segment in segments {
            var piece = AttributedString(segment.text)
            piece.foregroundColor = segment.isMatch ? Islands.searchMatch : Islands.foreground
            result.append(piece)
        }
        return result
    }

    struct Segment: Equatable {
        let text: String
        let isMatch: Bool
    }

    var segments: [Segment] {
        let string = text as NSString
        guard !ranges.isEmpty, string.length > 0 else {
            return [Segment(text: text, isMatch: false)]
        }

        var result: [Segment] = []
        var cursor = 0

        for range in ranges.sorted(by: { $0.location < $1.location }) {
            let start = max(0, min(range.location, string.length))
            let end = max(start, min(range.location + range.length, string.length))
            if start > cursor {
                result.append(Segment(
                    text: string.substring(with: NSRange(location: cursor, length: start - cursor)),
                    isMatch: false
                ))
            }
            if end > start {
                result.append(Segment(
                    text: string.substring(with: NSRange(location: start, length: end - start)),
                    isMatch: true
                ))
            }
            cursor = max(cursor, end)
        }

        if cursor < string.length {
            result.append(Segment(
                text: string.substring(from: cursor),
                isMatch: false
            ))
        }

        return result
    }
}

struct SearchEverywherePreviewView: View {
    let preview: SearchEverywherePreview

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(preview.title)
                    .font(Islands.smallFont)
                    .foregroundStyle(Islands.foreground)
                    .lineLimit(1)
                Text(preview.subtitle)
                    .font(Islands.smallFont)
                    .foregroundStyle(Islands.secondaryForeground)
                    .lineLimit(1)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(preview.lines) { line in
                        HStack(spacing: 10) {
                            Text("\(line.number)")
                                .font(Islands.codeFont)
                                .foregroundStyle(line.isTarget ? Islands.lineNumberCaretRow : Islands.lineNumber)
                                .frame(width: 40, alignment: .trailing)
                            Text(line.text.isEmpty ? " " : line.text)
                                .font(Islands.codeFont)
                                .foregroundStyle(Islands.editorForeground)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer(minLength: 0)
                        }
                        .frame(height: 17)
                        .background(line.isTarget ? Islands.caretRow : Color.clear)
                        .padding(.horizontal, 8)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .frame(height: 214)
    }
}
