import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct LanguageServerSettingsCoverageTests {
    private func decode(_ json: String) throws -> SettingsData.LanguageServerSettings {
        try JSONDecoder().decode(SettingsData.LanguageServerSettings.self, from: Data(json.utf8))
    }

    @Test
    func defaultSettingsHaveNoInstalledServers() {
        let settings = SettingsData.LanguageServerSettings()

        #expect(settings.installedLanguageServers.isEmpty)
    }

    @Test
    func searchKeysCoverTheLanguageServerVocabulary() {
        let keys = SettingsData.LanguageServerSettings().searchKeys

        #expect(keys == ["Language Servers", "LSP Binaries", "Linters", "Formatters", "Debug Protocol", "DAP"])
    }

    @Test
    func decodingWithoutTheKeyFallsBackToNoServers() throws {
        #expect(try decode("{}").installedLanguageServers.isEmpty)
    }

    @Test
    func decodingKeepsInstalledServers() throws {
        let settings = try decode(
            #"{"installedLanguageServers":{"alpha":{"packageName":"alpha","isEnabled":false,"version":"2.0"}}}"#
        )

        #expect(settings.installedLanguageServers["alpha"]
            == SettingsData.InstalledLanguageServer(packageName: "alpha", isEnabled: false, version: "2.0"))
    }

    @Test
    func encodingRoundTripsInstalledServers() throws {
        var settings = SettingsData.LanguageServerSettings()
        settings.installedLanguageServers["beta"] = SettingsData.InstalledLanguageServer(
            packageName: "beta",
            isEnabled: true,
            version: "1"
        )

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(SettingsData.LanguageServerSettings.self, from: data)

        #expect(decoded == settings)
    }
}
