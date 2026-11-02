import SwiftUI

struct SettingsSidebarView: View {
    @Binding var searchText: String
    @Binding var selectedPage: SettingsPage.Name
    var showsDeveloperPage: Bool

    @State private var collapsedCategories: Set<SettingsPage.Category> = []

    private var isSearching: Bool {
        !query.isEmpty
    }

    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var nodes: [SettingsCategoryNode] {
        SettingsNavigation.nodes(query: query, showsDeveloperPage: showsDeveloperPage)
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingsSearchField("Search", text: $searchText)
                .padding(.horizontal, 8)
                .padding(.top, 10)
                .padding(.bottom, 8)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    if nodes.isEmpty {
                        Text("No matching settings")
                            .font(Islands.smallFont)
                            .foregroundStyle(Islands.secondaryForeground)
                            .padding(.horizontal, 12)
                            .padding(.top, 6)
                    }
                    ForEach(nodes) { node in
                        categoryRow(node)
                        if isExpanded(node.category) {
                            ForEach(node.pages) { page in
                                SettingsPageRow(
                                    node: page,
                                    searchText: query,
                                    isSelected: page.name == selectedPage,
                                    onSelect: { selectedPage = page.name }
                                )
                                ForEach(page.matchingSettings, id: \.self) { setting in
                                    SettingsSettingRow(title: setting) {
                                        selectedPage = page.name
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Islands.frame)
        .onChange(of: searchText) { _, _ in
            selectFirstVisiblePageIfNeeded()
        }
        .onChange(of: showsDeveloperPage) { _, showsDeveloperPage in
            if !showsDeveloperPage && selectedPage == .developer {
                selectedPage = SettingsNavigation.defaultPage
            }
        }
    }

    private func isExpanded(_ category: SettingsPage.Category) -> Bool {
        isSearching || !collapsedCategories.contains(category)
    }

    private func categoryRow(_ node: SettingsCategoryNode) -> some View {
        HStack(spacing: 0) {
            Image(isExpanded(node.category) ? "general/chevronDown" : "general/chevronRight")
                .resizable()
                .interpolation(.high)
                .frame(width: 12, height: 12)
                .padding(.trailing, 4)
            Text(node.category.rawValue)
                .font(.system(size: Islands.uiFontSize, weight: .semibold))
                .foregroundStyle(Islands.foreground)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .frame(height: Islands.treeRowHeight + 4)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isSearching else { return }
            if collapsedCategories.contains(node.category) {
                collapsedCategories.remove(node.category)
            } else {
                collapsedCategories.insert(node.category)
            }
        }
    }

    private func selectFirstVisiblePageIfNeeded() {
        let names = SettingsNavigation.visiblePageNames(nodes)
        guard let first = names.first else { return }
        if !names.contains(selectedPage) {
            selectedPage = first
        }
    }
}

private struct SettingsPageRow: View {
    let node: SettingsPageNode
    let searchText: String
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: 16, height: 1)
            node.name.rawValue.highlightOccurrences(searchText)
                .font(Islands.uiFont)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .frame(height: Islands.treeRowHeight)
        .background {
            RoundedRectangle(cornerRadius: Islands.rowRadius)
                .fill(isSelected ? Islands.selection : (isHovering ? Islands.hover : Color.clear))
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(perform: onSelect)
    }
}

private struct SettingsSettingRow: View {
    let title: String
    let onSelect: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: 32, height: 1)
            Text(title)
                .font(Islands.smallFont)
                .foregroundStyle(Islands.secondaryForeground)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .frame(height: Islands.treeRowHeight - 2)
        .background {
            RoundedRectangle(cornerRadius: Islands.rowRadius)
                .fill(isHovering ? Islands.hover : Color.clear)
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(perform: onSelect)
    }
}
