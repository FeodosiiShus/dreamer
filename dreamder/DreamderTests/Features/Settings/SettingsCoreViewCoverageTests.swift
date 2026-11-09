import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
private final class SettingsCorePageBox {
    var page: SettingsPage.Name

    init(_ page: SettingsPage.Name) {
        self.page = page
    }

    var binding: Binding<SettingsPage.Name> {
        Binding(get: { self.page }, set: { self.page = $0 })
    }
}

@MainActor
private final class SettingsCoreTextBox {
    var text: String

    init(_ text: String) {
        self.text = text
    }

    var binding: Binding<String> {
        Binding(get: { self.text }, set: { self.text = $0 })
    }
}

@MainActor
private final class SettingsCoreRecorder {
    var pages: [SettingsPage.Name] = []
}

private struct SettingsCoreSidebarHarness: View {
    @Bindable var model: SettingsViewModel
    let sidebarModel: SettingsSidebarModel

    var body: some View {
        SettingsSidebarView(
            searchText: $model.searchText,
            selectedPage: $model.selectedPage,
            showsDeveloperPage: model.showsDeveloperPage,
            sidebarModel: sidebarModel
        )
    }
}

@MainActor
@Suite(.uiGate)
struct SettingsCoreViewCoverageTests {
    private func keyDown(_ keyCode: UInt16, window: NSWindow) throws -> NSEvent {
        try #require(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                characters: "",
                charactersIgnoringModifiers: "",
                isARepeat: false,
                keyCode: keyCode
            )
        )
    }

    @Test
    func everyPageIsRenderedByTheSettingsView() async throws {
        for name in SettingsPage.Name.allCases {
            let model = SettingsViewModel()
            model.selectedPage = name
            let hosted = HostedViewFixture.host(size: NSSize(width: 1100, height: 750)) {
                SettingsView(model: model)
            }
            try await hosted.settle(.milliseconds(60))
            #expect(hosted.renders())
            hosted.close()
            model.removeKeyDownMonitor()
        }
    }

    @Test
    func defaultSettingsViewRendersTheGeneralPage() async throws {
        let hosted = HostedViewFixture.host(size: NSSize(width: 1100, height: 750)) {
            SettingsView()
        }
        defer { hosted.close() }
        try await hosted.settle(.milliseconds(60))
        #expect(hosted.renders())
    }

    @Test
    func selectingPagesChangesWhatIsRendered() async throws {
        let model = SettingsViewModel()
        let hosted = HostedViewFixture.host(size: NSSize(width: 1100, height: 750)) {
            SettingsView(model: model)
        }
        defer {
            hosted.close()
            model.removeKeyDownMonitor()
        }
        try await hosted.settle(.milliseconds(60))
        let general = hosted.snapshot()

        model.select(.terminal)
        try await hosted.settle(.milliseconds(60))
        #expect(model.selectedPage == .terminal)
        #expect(HostedView.pixelsDiffer(general, hosted.snapshot()))
    }

    @Test
    func developerKeyTogglesTheDeveloperPageThroughTheLocalMonitor() async throws {
        let model = SettingsViewModel()
        let hosted = HostedViewFixture.host(size: NSSize(width: 1100, height: 750)) {
            SettingsView(model: model)
        }
        defer {
            hosted.close()
            model.removeKeyDownMonitor()
        }
        try await hosted.settle(.milliseconds(60))

        #expect(!model.handleKeyDown(keyCode: 111, windowNumber: hosted.window.windowNumber + 1))
        #expect(!model.showsDeveloperPage)

        NSApp.sendEvent(try keyDown(111, window: hosted.window))
        #expect(model.showsDeveloperPage)

        model.select(.developer)
        NSApp.sendEvent(try keyDown(111, window: hosted.window))
        #expect(!model.showsDeveloperPage)
        #expect(model.selectedPage == SettingsNavigation.defaultPage)
    }

    @Test
    func keyHandlingConsumesOnlyTheDeveloperKey() {
        let model = SettingsViewModel()
        #expect(!model.handleKeyDown(keyCode: 0))
        #expect(!model.showsDeveloperPage)
        #expect(model.handleKeyDown(keyCode: 111))
        #expect(model.showsDeveloperPage)
        model.select(.developer)
        #expect(model.handleKeyDown(keyCode: 111))
        #expect(model.selectedPage == .general)
        model.select(.terminal)
        #expect(model.handleKeyDown(keyCode: 111))
        #expect(model.selectedPage == .terminal)
    }

    @Test
    func developerKeyIsLeftToTheShortcutRecorderWhileRecording() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let keymap = Keymap(defaults: defaults)
        let model = SettingsViewModel(keymap: keymap)

        keymap.isRecording = true
        #expect(!model.handleKeyDown(keyCode: 111))
        #expect(!model.showsDeveloperPage)

        keymap.isRecording = false
        #expect(model.handleKeyDown(keyCode: 111))
        #expect(model.showsDeveloperPage)
    }

    @Test
    func monitorCanBeReplacedAndRemoved() {
        let model = SettingsViewModel()
        model.installKeyDownMonitor()
        model.installKeyDownMonitor()
        model.removeKeyDownMonitor()
        model.removeKeyDownMonitor()
        #expect(!model.backButtonVisible)
    }

    @Test
    func hidingTheDeveloperPageMovesTheSelectionAwayThroughTheSidebar() async throws {
        let model = SettingsViewModel()
        model.showsDeveloperPage = true
        model.selectedPage = .developer
        let sidebarModel = SettingsSidebarModel()
        let hosted = HostedViewFixture.host(size: NSSize(width: 300, height: 700)) {
            SettingsCoreSidebarHarness(model: model, sidebarModel: sidebarModel)
        }
        defer { hosted.close() }
        try await hosted.settle(.milliseconds(60))
        #expect(model.selectedPage == .developer)

        model.showsDeveloperPage = false
        try await hosted.settle(.milliseconds(60))
        #expect(model.selectedPage == SettingsNavigation.defaultPage)
    }

    @Test
    func searchingSelectsTheFirstVisiblePageAndListsMatchingSettings() async throws {
        let model = SettingsViewModel()
        let sidebarModel = SettingsSidebarModel()
        let hosted = HostedViewFixture.host(size: NSSize(width: 300, height: 700)) {
            SettingsCoreSidebarHarness(model: model, sidebarModel: sidebarModel)
        }
        defer { hosted.close() }
        try await hosted.settle(.milliseconds(60))
        let idle = hosted.snapshot()

        model.searchText = "Terminal"
        try await hosted.settle(.milliseconds(60))
        #expect(model.selectedPage == .keybindings)
        #expect(HostedView.pixelsDiffer(idle, hosted.snapshot()))

        let settingName = try #require(
            SettingsData().propertiesOf(.terminal)
                .filter(\.isSetting)
                .map(\.settingName)
                .first { name in
                    let nodes = SettingsNavigation.nodes(query: name, showsDeveloperPage: false)
                    return SettingsNavigation.visiblePageNames(nodes) == [.terminal]
                }
        )
        model.searchText = settingName
        try await hosted.settle(.milliseconds(60))
        #expect(model.selectedPage == .terminal)

        model.searchText = "zzzzzz"
        try await hosted.settle(.milliseconds(60))
        #expect(model.selectedPage == .terminal)

        model.searchText = ""
        try await hosted.settle(.milliseconds(60))
        #expect(model.selectedPage == .terminal)
    }

    @Test
    func collapsedCategoriesHideTheirPages() async throws {
        let model = SettingsViewModel()
        let sidebarModel = SettingsSidebarModel()
        let hosted = HostedViewFixture.host(size: NSSize(width: 300, height: 700)) {
            SettingsCoreSidebarHarness(model: model, sidebarModel: sidebarModel)
        }
        defer { hosted.close() }
        try await hosted.settle(.milliseconds(60))
        let expanded = hosted.snapshot()

        sidebarModel.collapsedCategories = Set(SettingsPage.Category.allCases)
        try await hosted.settle(.milliseconds(60))
        #expect(HostedView.pixelsDiffer(expanded, hosted.snapshot()))
    }

    @Test
    func sidebarModelTogglesCategoriesOnlyOutsideOfSearch() {
        let model = SettingsSidebarModel()
        #expect(model.isExpanded(.editor, isSearching: false))
        model.toggle(.editor, isSearching: false)
        #expect(!model.isExpanded(.editor, isSearching: false))
        #expect(model.isExpanded(.editor, isSearching: true))
        model.toggle(.editor, isSearching: true)
        #expect(model.collapsedCategories == [.editor])
        model.toggle(.editor, isSearching: false)
        #expect(model.collapsedCategories.isEmpty)
    }

    @Test
    func categoryRowTogglesItsCategory() {
        let model = SettingsSidebarModel()
        let row = SettingsCategoryRow(category: .tools, isSearching: false, model: model)
        row.toggle()
        #expect(model.collapsedCategories == [.tools])
        row.toggle()
        #expect(model.collapsedCategories.isEmpty)
    }

    @Test
    func pageAndSettingRowsSelectTheirPage() {
        let box = SettingsCorePageBox(.general)
        let node = SettingsPageNode(name: .terminal, matchingSettings: [])
        let pageRow = SettingsPageRow(node: node, searchText: "", selectedPage: box.binding)
        pageRow.setHovering(true)
        pageRow.setHovering(false)
        pageRow.select()
        #expect(box.page == .terminal)

        let settingRow = SettingsSettingRow(title: "Font", page: .search, selectedPage: box.binding)
        settingRow.setHovering(true)
        settingRow.select()
        #expect(box.page == .search)
    }

    @Test
    func pageSelectionAfterSearchKeepsOrRepairsTheSelection() {
        let keys: [SettingsPage.Name: [String]] = [:]
        let all = SettingsNavigation.filter(searchKeys: keys, query: "")
        #expect(SettingsNavigation.pageSelection(afterSearch: all, selected: .terminal) == .terminal)
        #expect(SettingsNavigation.pageSelection(afterSearch: [], selected: .terminal) == .terminal)
        let terminalOnly = SettingsNavigation.filter(searchKeys: keys, query: "Terminal")
        #expect(SettingsNavigation.pageSelection(afterSearch: terminalOnly, selected: .general) == .terminal)
    }

    @Test
    func pageSelectionAfterDeveloperVisibilityLeavesTheDeveloperPageWhenHidden() {
        #expect(SettingsNavigation.pageSelection(afterDeveloperPageVisibility: false, selected: .developer) == .general)
        #expect(SettingsNavigation.pageSelection(afterDeveloperPageVisibility: true, selected: .developer) == .developer)
        #expect(SettingsNavigation.pageSelection(afterDeveloperPageVisibility: false, selected: .search) == .search)
    }

    @Test
    func navigationNodesUseTheRealSettingsAndShortcuts() {
        let all = SettingsNavigation.nodes(query: "", showsDeveloperPage: true)
        #expect(all.map(\.id) == SettingsPage.Category.allCases)
        #expect(all.flatMap(\.pages).map(\.id).contains(.developer))
        #expect(!SettingsNavigation.nodes(query: "", showsDeveloperPage: false).flatMap(\.pages).map(\.id).contains(.developer))
        #expect(SettingsNavigation.nodes(query: "Key Bindings", showsDeveloperPage: false).count == 1)
        #expect(SettingsNavigation.nodes(query: "zzzzzzzz", showsDeveloperPage: true).isEmpty)
    }

    @Test
    func headerSelectsTheFirstPageOfItsCategory() async throws {
        let recorder = SettingsCoreRecorder()
        let header = SettingsHeaderView(page: .general) { recorder.pages.append($0) }
        header.selectCategoryPage()
        #expect(recorder.pages == [.appearance])

        let orphan = SettingsHeaderView(page: .behavior) { recorder.pages.append($0) }
        orphan.selectCategoryPage()
        #expect(recorder.pages == [.appearance])

        let withCategory = HostedViewFixture.host(size: NSSize(width: 500, height: 60)) {
            SettingsHeaderView(page: .general) { _ in }
        }
        defer { withCategory.close() }
        let withoutCategory = HostedViewFixture.host(size: NSSize(width: 500, height: 60)) {
            SettingsHeaderView(page: .behavior) { _ in }
        }
        defer { withoutCategory.close() }
        try await withCategory.settle(.milliseconds(50))
        try await withoutCategory.settle(.milliseconds(50))
        #expect(withCategory.renders())
        #expect(withoutCategory.renders())
        #expect(HostedView.pixelsDiffer(withCategory.snapshot(), withoutCategory.snapshot()))
    }

    @Test
    func searchFieldClearsAndFocuses() async throws {
        let box = SettingsCoreTextBox("query")
        let field = SettingsSearchField("Search", text: box.binding)
        field.focus()
        field.clear()
        #expect(box.text.isEmpty)

        let model = SettingsViewModel()
        model.searchText = "abc"
        let hosted = HostedViewFixture.host(size: NSSize(width: 300, height: 60)) {
            SettingsCoreSearchHarness(model: model)
        }
        defer { hosted.close() }
        try await hosted.settle(.milliseconds(50))
        let filled = hosted.snapshot()
        model.searchText = ""
        try await hosted.settle(.milliseconds(50))
        #expect(HostedView.pixelsDiffer(filled, hosted.snapshot()))
    }

    @Test
    func settingsWindowConfiguresOnlyTheSettingsWindow() {
        let plain = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        plain.isReleasedWhenClosed = false
        SettingsWindow.configureSettingsWindow(in: [plain])
        #expect(plain.appearance?.name != .darkAqua)

        plain.identifier = NSUserInterfaceItemIdentifier(SceneID.settings.rawValue)
        SettingsWindow.configureSettingsWindow(in: [plain])
        #expect(plain.appearance?.name == .darkAqua)
        #expect(plain.tabbingMode == .disallowed)
        _ = SettingsWindow().body
    }

    @Test
    func settingsWindowContentConfiguresItsWindowOnAppear() async throws {
        let hosted = HostedViewFixture.host(size: NSSize(width: 1000, height: 750)) {
            SettingsWindowContent()
        }
        defer { hosted.close() }
        try await hosted.settle()
        hosted.window.identifier = NSUserInterfaceItemIdentifier(SceneID.settings.rawValue)
        SettingsWindow.configureSettingsWindow(in: [hosted.window])
        #expect(hosted.window.appearance?.name == .darkAqua)
        #expect(hosted.window.tabbingMode == .disallowed)
    }
}

private struct SettingsCoreSearchHarness: View {
    @Bindable var model: SettingsViewModel

    var body: some View {
        SettingsSearchField("Search", text: $model.searchText)
    }
}
