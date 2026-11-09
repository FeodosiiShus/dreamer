import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct SettingsFlushTests {
    private func settingsFile(in directory: URL) -> URL {
        directory.appending(path: "settings.json")
    }

    private func savedPreferences(in directory: URL) -> SettingsData? {
        guard let data = try? Data(contentsOf: settingsFile(in: directory)) else { return nil }
        return try? JSONDecoder().decode(SettingsData.self, from: data)
    }

    private func fileExists(in directory: URL) -> Bool {
        FileManager.default.fileExists(atPath: settingsFile(in: directory).path(percentEncoded: false))
    }

    @Test
    func flushWritesAPendingChangeImmediately() throws {
        try withTempDir { directory in
            let settings = Settings(baseURL: directory, clock: TestClock())
            settings.preferences.general.isAutoSaveOn = false

            settings.flushPendingSave()

            #expect(savedPreferences(in: directory)?.general.isAutoSaveOn == false)
        }
    }

    @Test
    func flushWithoutAChangeWritesNothing() throws {
        try withTempDir { directory in
            let settings = Settings(baseURL: directory, clock: TestClock())

            settings.flushPendingSave()

            #expect(!fileExists(in: directory))
        }
    }

    @Test
    func flushAfterASaveDoesNotWriteAgain() throws {
        try withTempDir { directory in
            let settings = Settings(baseURL: directory, clock: TestClock())
            settings.preferences.general.isAutoSaveOn = false
            settings.flushPendingSave()
            try FileManager.default.removeItem(at: settingsFile(in: directory))

            settings.flushPendingSave()

            #expect(!fileExists(in: directory))
        }
    }

    @Test
    func flushAfterRevertingToTheSavedValueWritesNothing() throws {
        try withTempDir { directory in
            let settings = Settings(baseURL: directory, clock: TestClock())
            settings.preferences.general.isAutoSaveOn = false
            settings.preferences.general.isAutoSaveOn = true

            settings.flushPendingSave()

            #expect(!fileExists(in: directory))
        }
    }

    @Test
    func aFailedFlushKeepsTheChangePending() throws {
        try withTempDir { directory in
            let missing = directory.appending(path: "missing", directoryHint: .isDirectory)
            let settings = Settings(baseURL: missing, clock: TestClock())
            try FileManager.default.removeItem(at: settings.baseURL)
            settings.preferences.general.isAutoSaveOn = false
            settings.flushPendingSave()
            try FileManager.default.createDirectory(at: settings.baseURL, withIntermediateDirectories: true)

            settings.flushPendingSave()

            #expect(savedPreferences(in: settings.baseURL)?.general.isAutoSaveOn == false)
        }
    }

    @Test
    func theDebounceWritesAfterTheDelayAndRewritesLaterChanges() async throws {
        try await withTempDir { directory in
            let clock = TestClock()
            let settings = Settings(baseURL: directory, clock: clock)

            settings.preferences.general.isAutoSaveOn = false
            try await clock.waitForSleepers()
            #expect(!fileExists(in: directory))
            clock.advance(by: Settings.saveDebounce)
            try await eventually { savedPreferences(in: directory)?.general.isAutoSaveOn == false }

            settings.preferences.general.isAutoSaveOn = true
            try await clock.waitForSleepers()
            clock.advance(by: Settings.saveDebounce)
            try await eventually { savedPreferences(in: directory)?.general.isAutoSaveOn == true }
        }
    }

    @Test
    func aLaterChangeRestartsTheDebounce() async throws {
        try await withTempDir { directory in
            let clock = TestClock()
            let settings = Settings(baseURL: directory, clock: clock)

            settings.preferences.general.isAutoSaveOn = false
            try await clock.waitForSleepers()
            clock.advance(by: .seconds(1))
            settings.preferences.general.dimEditorsWithoutFocus = true
            let restartedDeadline = TestClock.Instant(offset: Settings.saveDebounce)
            try await eventually { clock.pendingDeadlines.contains { $0 > restartedDeadline } }
            clock.advance(by: .seconds(1))
            #expect(!fileExists(in: directory))
            clock.advance(by: Settings.saveDebounce)

            try await eventually { savedPreferences(in: directory)?.general.dimEditorsWithoutFocus == true }
            #expect(savedPreferences(in: directory)?.general.isAutoSaveOn == false)
        }
    }

    @Test
    func releasingTheSettingsFlushesAPendingChange() throws {
        try withTempDir { directory in
            var settings: Settings? = Settings(baseURL: directory, clock: TestClock())
            settings?.preferences.general.isAutoSaveOn = false

            settings = nil

            #expect(savedPreferences(in: directory)?.general.isAutoSaveOn == false)
        }
    }
}
