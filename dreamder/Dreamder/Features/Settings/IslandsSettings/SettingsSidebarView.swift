import SwiftUI

@Observable
final class SettingsSidebarModel {
    var collapsedCategories: Set<SettingsPage.Category> = []

    func isExpanded(_ category: SettingsPage.Category, isSearching: Bool) -> Bool {
        isSearching || !collapsedCategories.contains(category)
    }

    func toggle(_ category: SettingsPage.Category, isSearching: Bool) {
        guard !isSearching else { return }
        if collapsedCategories.remove(category) == nil {
            collapsedCategories.insert(category)
        }
    }
}

struct SettingsSidebarView: View {
    @Binding var searchText: String
    @Binding var selectedPage: SettingsPage.Name
    var showsDeveloperPage: Bool

    @State private var sidebarModel: SettingsSidebarModel

    init(
        searchText: Binding<String>,
        selectedPage: Binding<SettingsPage.Name>,
        showsDeveloperPage: Bool,
        sidebarModel: SettingsSidebarModel = SettingsSidebarModel()
    ) {
        self._searchText = searchText
        self._selectedPage = selectedPage
        self.showsDeveloperPage = showsDeveloperPage
        self._sidebarModel = State(initialValue: sidebarModel)
    }

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
                        SettingsCategoryRow(category: node.category, isSearching: isSearching, model: sidebarModel)
                        if sidebarModel.isExpanded(node.category, isSearching: isSearching) {
                            ForEach(node.pages) { page in
                                SettingsPageRow(node: page, searchText: query, selectedPage: $selectedPage)
                                ForEach(page.matchingSettings, id: \.self) { setting in
                                    SettingsSettingRow(title: setting, page: page.name, selectedPage: $selectedPage)
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
            selectedPage = SettingsNavigation.pageSelection(afterSearch: nodes, selected: selectedPage)
        }
        .onChange(of: showsDeveloperPage) { _, showsDeveloperPage in
            selectedPage = SettingsNavigation.pageSelection(
                afterDeveloperPageVisibility: showsDeveloperPage,
                selected: selectedPage
            )
        }
    }
}

struct SettingsCategoryRow: View {
    let category: SettingsPage.Category
    let isSearching: Bool
    let model: SettingsSidebarModel

    var body: some View {
        HStack(spacing: 0) {
            Image(model.isExpanded(category, isSearching: isSearching) ? "general/chevronDown" : "general/chevronRight")
                .resizable()
                .interpolation(.high)
                .frame(width: 12, height: 12)
                .padding(.trailing, 4)
            Text(category.rawValue)
                .font(.system(size: Islands.uiFontSize, weight: .semibold))
                .foregroundStyle(Islands.foreground)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .frame(height: Islands.treeRowHeight + 4)
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
    }

    func toggle() {
        model.toggle(category, isSearching: isSearching)
    }
}

struct SettingsPageRow: View {
    let node: SettingsPageNode
    let searchText: String
    @Binding var selectedPage: SettingsPage.Name

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
                .fill(selectedPage == node.name ? Islands.selection : (isHovering ? Islands.hover : Color.clear))
        }
        .contentShape(Rectangle())
        .onHover(perform: setHovering)
        .onTapGesture(perform: select)
    }

    func setHovering(_ hovering: Bool) {
        isHovering = hovering
    }

    func select() {
        selectedPage = node.name
    }
}

struct SettingsSettingRow: View {
    let title: String
    let page: SettingsPage.Name
    @Binding var selectedPage: SettingsPage.Name

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
        .onHover(perform: setHovering)
        .onTapGesture(perform: select)
    }

    func setHovering(_ hovering: Bool) {
        isHovering = hovering
    }

    func select() {
        selectedPage = page
    }
}
