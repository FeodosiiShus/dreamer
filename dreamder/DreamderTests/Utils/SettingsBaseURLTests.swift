import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct SettingsBaseURLTests {
    @Test
    func instanceKeepsTheInjectedBaseURL() throws {
        try withTempDir { dir in
            let settings = Settings(baseURL: dir)
            #expect(settings.baseURL == dir)
        }
    }

    @Test
    func loadsPersistedValuesFromTheInjectedDirectory() throws {
        try withTempDir { dir in
            let json = #"{"general": {"dimEditorsWithoutFocus": true}}"#
            try Data(json.utf8).write(to: dir.appending(path: "settings.json"))

            let settings = Settings(baseURL: dir)

            #expect(settings.preferences.general.dimEditorsWithoutFocus)
            #expect(settings.preferences.terminal == SettingsData().terminal)
        }
    }

    @Test
    func corruptFileFallsBackToDefaults() throws {
        try withTempDir { dir in
            try Data("{ not json".utf8).write(to: dir.appending(path: "settings.json"))

            let settings = Settings(baseURL: dir)

            #expect(settings.preferences == SettingsData())
        }
    }

    @Test
    func missingDirectoryIsCreated() throws {
        try withTempDir { dir in
            let nested = dir.appending(path: "nested", directoryHint: .isDirectory)
                .appending(path: "deeper", directoryHint: .isDirectory)

            let settings = Settings(baseURL: nested)

            var isDirectory: ObjCBool = false
            let path = nested.path(percentEncoded: false)
            #expect(FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory))
            #expect(isDirectory.boolValue)
            #expect(settings.preferences == SettingsData())
        }
    }

    @Test
    func instancesAreIndependentOfEachOther() throws {
        try withTempDir { first in
            try withTempDir { second in
                let one = Settings(baseURL: first)
                let two = Settings(baseURL: second)
                one.preferences.general.dimEditorsWithoutFocus = true
                #expect(two.preferences.general.dimEditorsWithoutFocus == false)
                #expect(one.baseURL != two.baseURL)
            }
        }
    }
}
