import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct AutosavePreferenceTests {
    @Test
    func theSharedSettingsDriveTheNonisolatedAutosaveFlag() throws {
        let previous = AutosavePreference.isEnabled.withLock { $0 }
        defer { AutosavePreference.isEnabled.withLock { $0 = previous } }
        try withTempDir { directory in
            let driving = Settings(baseURL: directory, drivesAutosavePreference: true)
            let document = CodeFileDocument()
            document.fileType = "public.plain-text"

            driving.preferences.general.isAutoSaveOn = true
            #expect(CodeFileDocument.autosavesInPlace)
            #expect(document.autosavingFileType == "public.plain-text")

            driving.preferences.general.isAutoSaveOn = false
            #expect(CodeFileDocument.autosavesInPlace == false)
            #expect(document.autosavingFileType == nil)
        }
    }

    @Test
    func otherSettingsInstancesLeaveTheFlagAlone() throws {
        let previous = AutosavePreference.isEnabled.withLock { $0 }
        defer { AutosavePreference.isEnabled.withLock { $0 = previous } }
        try withTempDir { directory in
            let driving = Settings(baseURL: directory.appending(path: "driving", directoryHint: .isDirectory), drivesAutosavePreference: true)
            driving.preferences.general.isAutoSaveOn = false
            let isolated = Settings(baseURL: directory.appending(path: "isolated", directoryHint: .isDirectory))

            isolated.preferences.general.isAutoSaveOn = true

            #expect(CodeFileDocument.autosavesInPlace == false)
        }
    }
}
