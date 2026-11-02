import Foundation

struct SettingsPageNode: Hashable, Identifiable {
    let name: SettingsPage.Name
    let matchingSettings: [String]

    var id: SettingsPage.Name { name }
}

struct SettingsCategoryNode: Hashable, Identifiable {
    let category: SettingsPage.Category
    let pages: [SettingsPageNode]

    var id: SettingsPage.Category { category }
}

enum SettingsNavigation {
    static var defaultPage: SettingsPage.Name {
        .general
    }

    static func nodes(query: String, showsDeveloperPage: Bool) -> [SettingsCategoryNode] {
        filter(
            searchKeys: searchKeys,
            query: query,
            showsDeveloperPage: showsDeveloperPage
        )
    }

    static func filter(
        categories: [SettingsPage.Category] = SettingsPage.Category.allCases,
        searchKeys: [SettingsPage.Name: [String]],
        query: String,
        showsDeveloperPage: Bool = true
    ) -> [SettingsCategoryNode] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return categories.compactMap { category in
            let pages = category.pages
                .filter { $0 != .developer || showsDeveloperPage }
                .compactMap { name -> SettingsPageNode? in
                    guard !needle.isEmpty else {
                        return SettingsPageNode(name: name, matchingSettings: [])
                    }
                    let matching = unique((searchKeys[name] ?? []).filter { $0.lowercased().contains(needle) })
                    guard name.rawValue.lowercased().contains(needle) || !matching.isEmpty else {
                        return nil
                    }
                    return SettingsPageNode(name: name, matchingSettings: matching)
                }
            guard !pages.isEmpty else { return nil }
            return SettingsCategoryNode(category: category, pages: pages)
        }
    }

    static func visiblePageNames(_ nodes: [SettingsCategoryNode]) -> [SettingsPage.Name] {
        nodes.flatMap { $0.pages.map(\.name) }
    }

    private static let searchKeys: [SettingsPage.Name: [String]] = {
        var keys: [SettingsPage.Name: [String]] = [:]
        for name in SettingsPage.Category.allCases.flatMap(\.pages) {
            let settings = PageAndSettings(SettingsPage(name)).settings
                .filter(\.isSetting)
                .map(\.settingName)
            let shortcuts = name == .keybindings
                ? KeybindingManager.shared.keyboardShortcuts.values.map(\.description)
                : []
            keys[name] = unique(settings + shortcuts)
        }
        return keys
    }()

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
