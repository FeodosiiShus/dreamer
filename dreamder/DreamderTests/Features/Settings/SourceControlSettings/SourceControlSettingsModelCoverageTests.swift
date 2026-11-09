import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct SourceControlSettingsModelCoverageTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    @Test
    func defaultsEnableEverythingAndLeaveGitMergeCommitsHidden() {
        let settings = SettingsData.SourceControlSettings()

        #expect(settings.general.sourceControlIsEnabled)
        #expect(settings.general.refreshStatusLocally)
        #expect(settings.general.fetchRefreshServerStatus)
        #expect(settings.general.addRemoveAutomatically)
        #expect(settings.general.selectFilesToCommit)
        #expect(settings.general.showSourceControlChanges)
        #expect(settings.general.includeUpstreamChanges)
        #expect(settings.general.revisionComparisonLayout == .localLeft)
        #expect(settings.general.controlNavigatorOrder == .sortByName)
        #expect(settings.git.showMergeCommitsPerFileLog == false)
    }

    @Test
    func searchKeysListEveryPageSetting() {
        let keys = SettingsData.SourceControlSettings().searchKeys

        #expect(keys.count == 16)
        #expect(keys.contains("Enable source control"))
        #expect(keys.contains("Show merge commits in per-file log"))
    }

    @Test
    func emptyJsonDecodesToDefaults() throws {
        let settings = try decode(SettingsData.SourceControlSettings.self, "{}")

        #expect(settings == SettingsData.SourceControlSettings())
    }

    @Test
    func emptyGeneralAndGitObjectsDecodeToDefaults() throws {
        let settings = try decode(SettingsData.SourceControlSettings.self, #"{"general":{},"git":{}}"#)

        #expect(settings == SettingsData.SourceControlSettings())
        #expect(try decode(SettingsData.SourceControlGeneral.self, "{}") == SettingsData.SourceControlGeneral())
        #expect(try decode(SettingsData.SourceControlGit.self, "{}") == SettingsData.SourceControlGit())
    }

    @Test
    func storedValuesOverrideEveryDefault() throws {
        let json = """
        {
          "general": {
            "sourceControlIsEnabled": false,
            "refreshStatusLocally": false,
            "fetchRefreshServerStatus": false,
            "addRemoveAutomatically": false,
            "selectFilesToCommit": false,
            "showSourceControlChanges": false,
            "includeUpstreamChanges": false,
            "revisionComparisonLayout": "localRight",
            "controlNavigatorOrder": "sortByDate"
          },
          "git": { "showMergeCommitsPerFileLog": true }
        }
        """

        let settings = try decode(SettingsData.SourceControlSettings.self, json)

        #expect(settings.general.sourceControlIsEnabled == false)
        #expect(settings.general.refreshStatusLocally == false)
        #expect(settings.general.fetchRefreshServerStatus == false)
        #expect(settings.general.addRemoveAutomatically == false)
        #expect(settings.general.selectFilesToCommit == false)
        #expect(settings.general.showSourceControlChanges == false)
        #expect(settings.general.includeUpstreamChanges == false)
        #expect(settings.general.revisionComparisonLayout == .localRight)
        #expect(settings.general.controlNavigatorOrder == .sortByDate)
        #expect(settings.git.showMergeCommitsPerFileLog)
    }

    @Test
    func encodingRoundTripsChangedValues() throws {
        var settings = SettingsData.SourceControlSettings()
        settings.general.revisionComparisonLayout = .localRight
        settings.general.controlNavigatorOrder = .sortByDate
        settings.git.showMergeCommitsPerFileLog = true

        let data = try JSONEncoder().encode(settings)

        #expect(try JSONDecoder().decode(SettingsData.SourceControlSettings.self, from: data) == settings)
    }
}
