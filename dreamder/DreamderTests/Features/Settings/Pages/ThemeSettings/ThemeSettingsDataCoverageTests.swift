import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct ThemeSettingsDataCoverageTests {
    private func decode(_ json: String) throws -> SettingsData.ThemeSettings {
        try JSONDecoder().decode(SettingsData.ThemeSettings.self, from: Data(json.utf8))
    }

    @Test
    func defaultsMatchTheBundledDarkTheme() {
        let settings = SettingsData.ThemeSettings()

        #expect(settings.selectedDarkTheme == "Islands Dark")
        #expect(settings.selectedLightTheme == "default.light")
        #expect(settings.selectedTheme == "Islands Dark")
        #expect(settings.useThemeBackground)
        #expect(settings.matchAppearance)
        #expect(settings.overrides.isEmpty)
    }

    @Test
    func searchKeysListTheThemeSettingsAndBundledNames() {
        let keys = SettingsData.ThemeSettings().searchKeys

        #expect(keys.count == 11)
        #expect(keys.contains("Always use dark terminal appearance"))
        #expect(keys.contains("Use theme background"))
        #expect(keys.contains("GitHub Dark"))
    }

    @Test
    func decodingEmptyDocumentKeepsDefaults() throws {
        let settings = try decode("{}")

        #expect(settings == SettingsData.ThemeSettings())
    }

    @Test
    func decodingReadsEveryStoredKey() throws {
        let json = """
        {
          "selectedDarkTheme": "Dark One",
          "selectedLightTheme": "Light One",
          "selectedTheme": "Light One",
          "useThemeBackground": false,
          "matchAppearance": false,
          "overrides": {"Dark One": {"editor": {"text": {"color": "#ffffff"}}}}
        }
        """

        let settings = try decode(json)

        #expect(settings.selectedDarkTheme == "Dark One")
        #expect(settings.selectedLightTheme == "Light One")
        #expect(settings.selectedTheme == "Light One")
        #expect(settings.useThemeBackground == false)
        #expect(settings.matchAppearance == false)
        #expect(settings.overrides["Dark One"]?["editor"]?["text"]?.color == "#ffffff")
    }

    @Test
    func themeSearchableStringIsItsIdentifier() {
        let theme = ThemeSettingsCoverageThemes.make(name: "searchable-theme", displayName: "Searchable")

        #expect(theme.searchableString == "searchable-theme")
    }

    @Test
    func themesAreFuzzySearchableByName() async {
        let themes = [
            ThemeSettingsCoverageThemes.make(name: "alpha-dark"),
            ThemeSettingsCoverageThemes.make(name: "beta-light", appearance: .light)
        ]

        let matches = await themes.fuzzySearch(query: "alpha")

        #expect(matches.map(\.item.name) == ["alpha-dark"])
    }
}
