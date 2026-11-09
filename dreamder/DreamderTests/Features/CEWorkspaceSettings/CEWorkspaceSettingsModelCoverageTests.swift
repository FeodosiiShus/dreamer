import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct CEWorkspaceSettingsModelCoverageTests {
    func makeSettings(in directory: URL) -> CEWorkspaceSettings {
        CEWorkspaceSettings(workspaceURL: directory)
    }

    func settingsFileExists(_ settings: CEWorkspaceSettings) -> Bool {
        FileManager.default.fileExists(atPath: settings.settingsURL.path(percentEncoded: false))
    }

    func folderExists(_ settings: CEWorkspaceSettings) -> Bool {
        FileManager.default.fileExists(atPath: settings.folderURL.path(percentEncoded: false))
    }

    @Test
    func projectSettingsDecodeDefaultsAndValue() throws {
        let empty = try JSONDecoder().decode(ProjectSettings.self, from: Data("{}".utf8))
        let named = try JSONDecoder().decode(ProjectSettings.self, from: Data(#"{"projectName":"Demo"}"#.utf8))

        #expect(empty.projectName.isEmpty)
        #expect(empty.isEmpty())
        #expect(named.projectName == "Demo")
        #expect(!named.isEmpty())
    }

    @Test
    func projectSettingsRoundTrip() throws {
        let project = ProjectSettings()
        project.projectName = "Demo"

        let decoded = try JSONDecoder().decode(ProjectSettings.self, from: JSONEncoder().encode(project))

        #expect(decoded.projectName == "Demo")
    }

    @Test
    func settingsDataDecodesDefaultsFromEmptyObject() throws {
        let data = try JSONDecoder().decode(CEWorkspaceSettingsData.self, from: Data("{}".utf8))

        #expect(data.project.isEmpty())
        #expect(data.tasks.isEmpty)
        #expect(data.isEmpty())
    }

    @Test
    func settingsDataEncodesNothingWhenEmpty() throws {
        let encoded = try JSONEncoder().encode(CEWorkspaceSettingsData())

        #expect(String(decoding: encoded, as: UTF8.self) == "{}")
    }

    @Test
    func settingsDataEncodesOnlyTheNonEmptySections() throws {
        let projectOnly = CEWorkspaceSettingsData()
        projectOnly.project.projectName = "Demo"
        let tasksOnly = CEWorkspaceSettingsData()
        tasksOnly.tasks = [CETask(name: "Build", command: "make")]

        let projectJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(projectOnly))
        let tasksJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(tasksOnly))
        let projectObject = try #require(projectJSON as? [String: Any])
        let tasksObject = try #require(tasksJSON as? [String: Any])

        #expect(Set(projectObject.keys) == ["project"])
        #expect(Set(tasksObject.keys) == ["tasks"])
        #expect(!projectOnly.isEmpty())
        #expect(!tasksOnly.isEmpty())
    }

    @Test
    func settingsDataRoundTripKeepsProjectAndTasks() throws {
        let data = CEWorkspaceSettingsData()
        data.project.projectName = "Demo"
        data.tasks = [CETask(name: "Build", command: "make"), CETask(name: "Test", command: "make test")]

        let decoded = try JSONDecoder().decode(CEWorkspaceSettingsData.self, from: JSONEncoder().encode(data))

        #expect(decoded.project.projectName == "Demo")
        #expect(decoded.tasks.map(\.name) == ["Build", "Test"])
        #expect(decoded.tasks.map(\.command) == ["make", "make test"])
    }

    @Test
    func settingsLiveInTheDreamderFolderOfTheWorkspace() throws {
        try withTempDir { directory in
            let settings = makeSettings(in: directory)
            defer { settings.cleanUp() }

            #expect(settings.folderURL == directory.appending(path: ".dreamder", directoryHint: .isDirectory))
            #expect(settings.settingsURL.lastPathComponent == "settings.json")
            #expect(settings.settings.isEmpty())
        }
    }

    @Test
    func savingPersistsPrettyJSONThatANewManagerLoads() throws {
        try withTempDir { directory in
            let settings = makeSettings(in: directory)
            defer { settings.cleanUp() }
            settings.settings.project.projectName = "Demo"
            settings.settings.tasks = [
                CETask(
                    name: "Build",
                    workingDirectory: "/work",
                    command: "make",
                    environmentVariables: [CETask.EnvironmentVariable(key: "A", value: "1")]
                )
            ]

            try settings.savePreferences()

            let text = try String(contentsOf: settings.settingsURL, encoding: .utf8)
            #expect(text.contains("\n"))
            #expect(text.contains("\"projectName\""))

            let reloaded = makeSettings(in: directory)
            defer { reloaded.cleanUp() }
            #expect(reloaded.settings.project.projectName == "Demo")
            let task = try #require(reloaded.settings.tasks.first)
            #expect(task.name == "Build")
            #expect(task.workingDirectory == "/work")
            #expect(task.command == "make")
            #expect(task.environmentVariablesDictionary == ["A": "1"])
        }
    }

    @Test
    func savingCreatesTheFolderOnDemand() throws {
        try withTempDir { directory in
            let settings = makeSettings(in: directory)
            defer { settings.cleanUp() }
            settings.settings.project.projectName = "Demo"
            #expect(!folderExists(settings))

            try settings.savePreferences()

            #expect(folderExists(settings))
            #expect(settingsFileExists(settings))
        }
    }

    @Test
    func savingTwiceReusesTheExistingFolder() throws {
        try withTempDir { directory in
            let settings = makeSettings(in: directory)
            defer { settings.cleanUp() }
            settings.settings.project.projectName = "Demo"
            try settings.savePreferences()
            settings.settings.project.projectName = "Renamed"

            try settings.savePreferences()

            let reloaded = makeSettings(in: directory)
            defer { reloaded.cleanUp() }
            #expect(reloaded.settings.project.projectName == "Renamed")
        }
    }

    @Test
    func savingEmptySettingsWithoutAFileDoesNothing() throws {
        try withTempDir { directory in
            let settings = makeSettings(in: directory)
            defer { settings.cleanUp() }

            try settings.savePreferences()

            #expect(!folderExists(settings))
        }
    }

    @Test
    func savingEmptySettingsRemovesTheFileAndTheEmptyFolder() throws {
        try withTempDir { directory in
            let settings = makeSettings(in: directory)
            defer { settings.cleanUp() }
            settings.settings.project.projectName = "Demo"
            try settings.savePreferences()
            #expect(settingsFileExists(settings))

            settings.settings.project.projectName = ""
            try settings.savePreferences()

            #expect(!settingsFileExists(settings))
            #expect(!folderExists(settings))
        }
    }

    @Test
    func savingEmptySettingsKeepsAFolderThatHoldsOtherFiles() throws {
        try withTempDir { directory in
            let settings = makeSettings(in: directory)
            defer { settings.cleanUp() }
            settings.settings.tasks = [CETask(name: "Build", command: "make")]
            try settings.savePreferences()
            let otherFile = settings.folderURL.appending(path: "other.txt")
            try Data("keep".utf8).write(to: otherFile)

            settings.settings.tasks = []
            try settings.savePreferences()

            #expect(!settingsFileExists(settings))
            #expect(FileManager.default.fileExists(atPath: otherFile.path(percentEncoded: false)))
        }
    }

    @Test
    func loadingIgnoresUndecodableSettingsFiles() throws {
        try withTempDir { directory in
            let folder = directory.appending(path: ".dreamder", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data("not json".utf8).write(to: folder.appending(path: "settings.json"))

            let settings = makeSettings(in: directory)
            defer { settings.cleanUp() }

            #expect(settings.settings.isEmpty())
        }
    }

    @Test
    func loadingReadsAHandWrittenSettingsFile() throws {
        try withTempDir { directory in
            let folder = directory.appending(path: ".dreamder", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let json = #"{"project":{"projectName":"Hand"},"tasks":[{"name":"Run","command":"echo hi"}]}"#
            try Data(json.utf8).write(to: folder.appending(path: "settings.json"))

            let settings = makeSettings(in: directory)
            defer { settings.cleanUp() }

            #expect(settings.settings.project.projectName == "Hand")
            #expect(settings.settings.tasks.map(\.name) == ["Run"])
        }
    }

    @Test
    func cleanUpIsIdempotent() throws {
        try withTempDir { directory in
            let settings = makeSettings(in: directory)

            settings.cleanUp()
            settings.cleanUp()

            #expect(settings.settings.isEmpty())
        }
    }
}
