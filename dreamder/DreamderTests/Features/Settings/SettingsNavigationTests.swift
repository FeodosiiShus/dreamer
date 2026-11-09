import Testing
@testable import Dreamder

@Suite
struct SettingsNavigationTests {
    private let keys: [SettingsPage.Name: [String]] = [
        .general: ["Reopen Window After Close", "File Icon Style"],
        .appearance: ["Appearance"],
        .keybindings: ["Copy command", "Paste command"],
        .textEditing: ["Line Height", "Show Invisibles"],
        .terminal: ["Shell", "Font Size"],
        .developer: ["Diagnostics"]
    ]

    @Test
    func everyPageWithAViewBelongsToExactlyOneCategory() {
        let listed = SettingsPage.Category.allCases.flatMap(\.pages)
        #expect(listed.count == Set(listed).count)
        for name in SettingsPage.Name.allCases {
            #expect(listed.contains(name) == (name.category != nil))
        }
    }

    @Test
    func categoriesFollowIntelliJOrder() {
        let nodes = SettingsNavigation.filter(searchKeys: keys, query: "")
        #expect(nodes.map(\.category) == [
            .appearanceAndBehavior,
            .keymap,
            .editor,
            .versionControl,
            .languagesAndFrameworks,
            .tools
        ])
        #expect(nodes.first?.pages.map(\.name) == [.appearance, .general])
    }

    @Test
    func pageNameFiltersTheTree() {
        let nodes = SettingsNavigation.filter(searchKeys: keys, query: "term")
        #expect(nodes.count == 1)
        #expect(nodes.first?.category == .tools)
        #expect(nodes.first?.pages.map(\.name) == [.terminal])
    }

    @Test
    func settingNameFiltersAndListsTheMatch() {
        let nodes = SettingsNavigation.filter(searchKeys: keys, query: "line height")
        #expect(nodes.count == 1)
        #expect(nodes.first?.category == .editor)
        #expect(nodes.first?.pages.first?.name == .textEditing)
        #expect(nodes.first?.pages.first?.matchingSettings == ["Line Height"])
    }

    @Test
    func pageMatchedByNameListsNoSettings() {
        let nodes = SettingsNavigation.filter(searchKeys: keys, query: "search")
        let page = nodes.flatMap(\.pages).first { $0.name == .search }
        #expect(page != nil)
        #expect(page?.matchingSettings.isEmpty == true)
    }

    @Test
    func matchingIsCaseInsensitiveAndTrimsWhitespace() {
        let nodes = SettingsNavigation.filter(searchKeys: keys, query: "  COPY ")
        #expect(nodes.flatMap(\.pages).map(\.name) == [.keybindings])
        #expect(nodes.flatMap(\.pages).first?.matchingSettings == ["Copy command"])
    }

    @Test
    func noMatchGivesAnEmptyTree() {
        #expect(SettingsNavigation.filter(searchKeys: keys, query: "zzz").isEmpty)
    }

    @Test
    func whitespaceOnlyQueryKeepsEveryPage() {
        let nodes = SettingsNavigation.filter(searchKeys: keys, query: "   ")
        #expect(nodes.flatMap(\.pages).allSatisfy { $0.matchingSettings.isEmpty })
        #expect(nodes.count == SettingsPage.Category.allCases.count)
    }

    @Test
    func developerPageNeedsTheDeveloperToggle() {
        let hidden = SettingsNavigation.filter(searchKeys: keys, query: "", showsDeveloperPage: false)
        #expect(!hidden.flatMap(\.pages).map(\.name).contains(.developer))

        let shown = SettingsNavigation.filter(searchKeys: keys, query: "diagnostics")
        #expect(shown.flatMap(\.pages).map(\.name) == [.developer])
    }

    @Test
    func duplicateSettingsAreListedOnce() {
        var duplicated = keys
        duplicated[.terminal] = ["Shell", "Shell"]
        let nodes = SettingsNavigation.filter(searchKeys: duplicated, query: "shell")
        #expect(nodes.flatMap(\.pages).first?.matchingSettings == ["Shell"])
    }

    @Test
    func visiblePageNamesFlattensTheCategories() {
        let nodes = SettingsNavigation.filter(searchKeys: keys, query: "")
        let names = SettingsNavigation.visiblePageNames(nodes)
        #expect(names.first == .appearance)
        #expect(names.count == SettingsPage.Category.allCases.flatMap(\.pages).count)
    }

    @Test
    func defaultPageIsGeneral() {
        #expect(SettingsNavigation.defaultPage == .general)
    }
}
