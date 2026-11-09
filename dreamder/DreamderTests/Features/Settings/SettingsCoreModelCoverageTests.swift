import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct SettingsCoreModelCoverageTests {
    @MainActor
    private struct SettingsCoreProbe {
        @AppSettings(\.general.dimEditorsWithoutFocus) var dim: Bool
    }

    @Test
    func appSettingsWrapperReadsAndWritesSharedPreferences() throws {
        try withTempDir { directory in
            let store = Settings(baseURL: directory)
            SettingsScope.$current.withValue(store) {
                let probe = SettingsCoreProbe()
                let original = store.preferences.general.dimEditorsWithoutFocus

                probe.dim = !original
                #expect(store.preferences.general.dimEditorsWithoutFocus == !original)
                #expect(probe.dim == !original)

                let binding = probe.$dim
                #expect(binding.wrappedValue == !original)
                binding.wrappedValue = original
                #expect(probe.dim == original)
                #expect(store.preferences.general.dimEditorsWithoutFocus == original)
            }
        }
    }

    @Test
    func defaultBaseURLUsesTemporaryDirectoryUnderTestsAndApplicationSupportOtherwise() {
        let testing = Settings.defaultBaseURL(environment: ["XCTestConfigurationFilePath": "/x"])
        #expect(testing.lastPathComponent == "DreamderTests")
        let shard = Settings.defaultBaseURL(environment: ["XCTestConfigurationFilePath": "/x", "DREAMDER_SHARD": "2"])
        #expect(shard.lastPathComponent == "DreamderTests-2")
        let production = Settings.defaultBaseURL(environment: [:])
        #expect(production.path(percentEncoded: false).contains("Library/Application Support/Dreamder"))
    }

    @Test
    func injectorPlacesPreferencesIntoTheEnvironment() async throws {
        let hosted = HostedViewFixture.host(size: NSSize(width: 100, height: 60)) {
            SettingsInjector {
                Text("Injected").padding()
            }
        }
        defer { hosted.close() }
        try await hosted.settle(.milliseconds(50))
        #expect(hosted.renders())
    }

    @Test
    func propertiesOfEveryPageNameAreListed() {
        let data = SettingsData()
        for name in SettingsPage.Name.allCases {
            let properties = data.propertiesOf(name)
            #expect(PageAndSettings(SettingsPage(name)).settings.map(\.settingName) == properties.map(\.settingName))
        }
        #expect(data.propertiesOf(.behavior).first?.settingName == "Error")
        #expect(data.propertiesOf(.general).allSatisfy { $0.isSetting })
    }

    @Test
    func pageAndSettingsKeepThePage() {
        let page = SettingsPage(.terminal)
        let combined = PageAndSettings(page)
        #expect(combined.page == page)
        #expect(combined != PageAndSettings(page))
    }

    @Test
    func settingsPageExposesItsFields() {
        let page = SettingsPage(.theme, baseColor: .red, icon: .system("gear"), isSetting: true, settingName: "Font")
        #expect(page.name == .theme)
        #expect(page.isSetting)
        #expect(page.settingName == "Font")
        #expect(page.icon == .system("gear"))
        #expect(page.baseColor != nil)
        #expect(String(describing: page.nameString).isEmpty == false)
        #expect(SettingsPage(.theme) != page)
        #expect(SettingsPage.Category.editor.id == "Editor")
    }

    @Test
    func globPatternRoundTripsThroughJSON() throws {
        let pattern = GlobPattern(value: "*.swift")
        let decoded = try JSONDecoder().decode(GlobPattern.self, from: JSONEncoder().encode(pattern))
        #expect(decoded == pattern)
        #expect(GlobPattern(value: "a").id != GlobPattern(value: "a").id)
    }

    @Test
    func settingsDataDecodesEmptyObjectToDefaults() throws {
        let decoded = try JSONDecoder().decode(SettingsData.self, from: Data("{}".utf8))
        #expect(decoded.terminal == SettingsData().terminal)
    }

    @Test
    func splitViewItemSwizzleBlocksCollapsingOnlyInTheSettingsWindow() {
        let settingsController = NSViewController()
        let otherController = NSViewController()
        let settingsItem = NSSplitViewItem(sidebarWithViewController: settingsController)
        let otherItem = NSSplitViewItem(sidebarWithViewController: otherController)
        let detachedItem = NSSplitViewItem(sidebarWithViewController: NSViewController())

        let settingsWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        settingsWindow.isReleasedWhenClosed = false
        settingsWindow.identifier = NSUserInterfaceItemIdentifier(SceneID.settings.rawValue)
        settingsWindow.contentView = settingsController.view
        let otherWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        otherWindow.isReleasedWhenClosed = false
        otherWindow.contentView = otherController.view

        func observe() -> [Bool] {
            [settingsItem.canCollapse, otherItem.canCollapse, detachedItem.canCollapse]
        }

        NSSplitViewItem.swizzle()
        let first = observe()
        NSSplitViewItem.swizzle()
        let second = observe()

        let observations = [first, second]
        #expect(observations.contains([false, true, true]))
        #expect(observations.contains([true, true, true]))

        NSSplitViewItem.exchange(Selector(("settingsCoreMissingA")), Selector(("settingsCoreMissingB")))
        #expect(observe() == second)
    }
}
