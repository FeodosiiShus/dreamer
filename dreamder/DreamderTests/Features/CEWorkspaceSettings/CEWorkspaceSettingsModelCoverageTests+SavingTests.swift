import Foundation
import Testing
@testable import Dreamder

@MainActor
extension CEWorkspaceSettingsModelCoverageTests {
    func savedText(_ settings: CEWorkspaceSettings) -> String? {
        try? String(contentsOf: settings.settingsURL, encoding: .utf8)
    }

    @Test
    func projectSettingsEncodeOnlyTheProjectName() throws {
        let project = ProjectSettings()
        project.projectName = "Demo"

        let object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(project)) as? [String: String]
        )

        #expect(object == ["projectName": "Demo"])
    }

    @Test
    func editingTheProjectNameIsSavedAfterTheDebounce() async throws {
        try await withTempDir { directory in
            let clock = TestClock()
            let settings = CEWorkspaceSettings(workspaceURL: directory, clock: clock)
            defer { settings.cleanUp() }

            settings.settings.project.projectName = "Demo"
            try await clock.waitForSleepers()
            #expect(!settingsFileExists(settings))
            clock.advance(by: CEWorkspaceSettings.saveDebounce)

            try await eventually { savedText(settings)?.contains("Demo") == true }
        }
    }

    @Test
    func editingATaskIsSavedAfterTheDebounce() async throws {
        try await withTempDir { directory in
            let clock = TestClock()
            let settings = CEWorkspaceSettings(workspaceURL: directory, clock: clock)
            defer { settings.cleanUp() }
            let task = CETask(name: "Build", command: "make")

            settings.settings.tasks = [task]
            try await clock.waitForSleepers()
            clock.advance(by: CEWorkspaceSettings.saveDebounce)
            try await eventually { savedText(settings)?.contains("make") == true }

            task.command = "make all"
            try await clock.waitForSleepers()
            clock.advance(by: CEWorkspaceSettings.saveDebounce)
            try await eventually { savedText(settings)?.contains("make all") == true }

            task.environmentVariables = [CETask.EnvironmentVariable(key: "KEY", value: "VALUE")]
            try await clock.waitForSleepers()
            clock.advance(by: CEWorkspaceSettings.saveDebounce)
            try await eventually { savedText(settings)?.contains("VALUE") == true }
        }
    }

    @Test
    func aLaterEditRestartsTheDebounce() async throws {
        try await withTempDir { directory in
            let clock = TestClock()
            let settings = CEWorkspaceSettings(workspaceURL: directory, clock: clock)
            defer { settings.cleanUp() }

            settings.settings.project.projectName = "First"
            try await clock.waitForSleepers()
            clock.advance(by: .seconds(1))
            settings.settings.project.projectName = "Second"
            try await eventually {
                clock.pendingDeadlines.contains { $0 > TestClock.Instant(offset: CEWorkspaceSettings.saveDebounce) }
            }
            clock.advance(by: .seconds(1))
            #expect(!settingsFileExists(settings))
            clock.advance(by: CEWorkspaceSettings.saveDebounce)

            try await eventually { savedText(settings)?.contains("Second") == true }
        }
    }

    @Test
    func cleanUpFlushesAPendingEditInsteadOfDroppingIt() throws {
        try withTempDir { directory in
            let settings = CEWorkspaceSettings(workspaceURL: directory, clock: TestClock())
            settings.settings.project.projectName = "Demo"

            settings.cleanUp()

            #expect(savedText(settings)?.contains("Demo") == true)
        }
    }

    @Test
    func releasingTheSettingsFlushesAPendingEdit() throws {
        try withTempDir { directory in
            var settings: CEWorkspaceSettings? = CEWorkspaceSettings(workspaceURL: directory, clock: TestClock())
            let url = try #require(settings?.settingsURL)
            settings?.settings.tasks = [CETask(name: "Build", command: "make")]

            settings = nil

            #expect((try? String(contentsOf: url, encoding: .utf8))?.contains("Build") == true)
        }
    }

    @Test
    func flushWithoutAnEditWritesNothing() throws {
        try withTempDir { directory in
            let settings = CEWorkspaceSettings(workspaceURL: directory, clock: TestClock())
            defer { settings.cleanUp() }

            settings.flushPendingSave()

            #expect(!folderExists(settings))
        }
    }

    @Test
    func flushAfterAnExplicitSaveDoesNotWriteAgain() throws {
        try withTempDir { directory in
            let settings = CEWorkspaceSettings(workspaceURL: directory, clock: TestClock())
            defer { settings.cleanUp() }
            settings.settings.project.projectName = "Demo"
            try settings.savePreferences()
            try FileManager.default.removeItem(at: settings.settingsURL)

            settings.flushPendingSave()

            #expect(!settingsFileExists(settings))
        }
    }

    @Test
    func flushingAnEmptiedSettingsFileRemovesIt() throws {
        try withTempDir { directory in
            let settings = CEWorkspaceSettings(workspaceURL: directory, clock: TestClock())
            defer { settings.cleanUp() }
            settings.settings.project.projectName = "Demo"
            try settings.savePreferences()

            settings.settings.project.projectName = ""
            settings.flushPendingSave()

            #expect(!settingsFileExists(settings))
        }
    }

    @Test
    func aFailedFlushKeepsTheEditPending() throws {
        try withTempDir { directory in
            let blocker = directory.appending(path: "blocker")
            try Data().write(to: blocker)
            let settings = CEWorkspaceSettings(workspaceURL: blocker, clock: TestClock())
            settings.settings.project.projectName = "Demo"
            settings.flushPendingSave()
            try FileManager.default.removeItem(at: blocker)
            try FileManager.default.createDirectory(at: blocker, withIntermediateDirectories: true)

            settings.flushPendingSave()

            #expect(savedText(settings)?.contains("Demo") == true)
        }
    }
}
