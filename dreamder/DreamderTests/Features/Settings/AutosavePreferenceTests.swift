import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct AutosavePreferenceTests {
    private func writeSavedAutosavePreference(_ isOn: Bool, in directory: URL) throws {
        let json = #"{"general": {"isAutoSaveOn": \#(isOn)}}"#
        try Data(json.utf8).write(to: directory.appending(path: "settings.json"))
    }

    @Test
    func aFlagStartsDisabledUnlessToldOtherwise() {
        #expect(AutosaveFlag().isEnabled == false)
        #expect(AutosaveFlag(isEnabled: true).isEnabled)
    }

    @Test
    func aFlagKeepsTheLastValueItWasSetTo() {
        let flag = AutosaveFlag()

        flag.set(true)
        #expect(flag.isEnabled)

        flag.set(false)
        #expect(flag.isEnabled == false)
    }

    @Test
    func settingsDriveTheirFlagOnLoadAndOnEveryChange() throws {
        try withTempDir { directory in
            let flag = AutosaveFlag(isEnabled: false)
            let driving = Settings(baseURL: directory, autosaveFlag: flag)
            #expect(flag.isEnabled)

            driving.preferences.general.isAutoSaveOn = false
            #expect(flag.isEnabled == false)

            driving.preferences.general.isAutoSaveOn = true
            #expect(flag.isEnabled)
        }
    }

    @Test
    func otherSettingsInstancesLeaveTheFlagAlone() throws {
        try withTempDir { directory in
            let flag = AutosaveFlag()
            let driving = Settings(
                baseURL: directory.appending(path: "driving", directoryHint: .isDirectory),
                autosaveFlag: flag
            )
            driving.preferences.general.isAutoSaveOn = false
            let isolated = Settings(baseURL: directory.appending(path: "isolated", directoryHint: .isDirectory))

            isolated.preferences.general.isAutoSaveOn = true

            #expect(flag.isEnabled == false)
        }
    }

    @Test
    func aSavedAutosavePreferenceAppliesWhenTheSettingsLoad() throws {
        try withTempDir { directory in
            try writeSavedAutosavePreference(true, in: directory)
            let flag = AutosaveFlag(isEnabled: false)

            let driving = Settings(baseURL: directory, autosaveFlag: flag)

            #expect(driving.preferences.general.isAutoSaveOn)
            #expect(flag.isEnabled)
        }
    }

    @Test
    func aSavedDisabledPreferenceTurnsTheFlagOffWhenTheSettingsLoad() throws {
        try withTempDir { directory in
            try writeSavedAutosavePreference(false, in: directory)
            let flag = AutosaveFlag(isEnabled: true)

            let driving = Settings(baseURL: directory, autosaveFlag: flag)

            #expect(driving.preferences.general.isAutoSaveOn == false)
            #expect(flag.isEnabled == false)
        }
    }

    @Test
    func aSavedAutosavePreferenceIsIgnoredByInstancesThatDoNotDriveAFlag() throws {
        try withTempDir { directory in
            try writeSavedAutosavePreference(true, in: directory)
            let flag = AutosaveFlag(isEnabled: false)

            let isolated = Settings(baseURL: directory)

            #expect(isolated.preferences.general.isAutoSaveOn)
            #expect(flag.isEnabled == false)
        }
    }

    @Test
    func documentsReadTheProcessWideFlagWithoutAnyoneWritingIt() {
        let document = CodeFileDocument()
        document.fileType = "public.plain-text"
        let expectsAutosave = AutosavePreference.shared.isEnabled

        #expect(CodeFileDocument.autosavesInPlace == expectsAutosave)
        #expect(document.autosavingFileType == (expectsAutosave ? "public.plain-text" : nil))
    }

    @Test
    func theSharedSettingsDriveTheProcessWideFlagOutsideATestHost() {
        #expect(Settings.processWideAutosaveFlag(environment: [:]) === AutosavePreference.shared)
        #expect(Settings.processWideAutosaveFlag(environment: ["DREAMDER_SHARD": "1"]) === AutosavePreference.shared)
    }

    @Test
    func theSharedSettingsDriveNoFlagInsideATestHost() {
        let environment = [TestHost.environmentKey: "/tmp/host.xctestconfiguration"]

        #expect(Settings.processWideAutosaveFlag(environment: environment) == nil)
    }
}
