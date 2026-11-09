import Foundation
import Synchronization
import Testing
@testable import Dreamder

private final class ThreadRecorder: Sendable {
    private let flags = Mutex<[Bool]>([])

    func record() {
        flags.withLock { $0.append(Thread.isMainThread) }
    }

    var recorded: [Bool] {
        flags.withLock { $0 }
    }
}

@MainActor
private final class RunRecordingTaskManager: TaskManager {
    private(set) var ranTasks: [CETask] = []

    override func runTask(task: CETask) async {
        ranTasks.append(task)
    }
}

@MainActor
@Suite(.serialized, .uiGate)
struct TaskManagerRunConfigurationsTests {
    private let fixture: TasksCoverageFixture
    private let leases = PooledDefaultsLeases()
    private let settings: CEWorkspaceSettingsData

    init() throws {
        fixture = try TasksCoverageFixture()
        settings = try JSONDecoder().decode(CEWorkspaceSettingsData.self, from: Data("{}".utf8))
    }

    private func makeDefaults() throws -> UserDefaults {
        try leases.make()
    }

    private func writePackage(in directory: URL, scripts: [String: String] = ["dev": "vite", "build": "vite build"]) throws {
        let object = ["scripts": scripts]
        let data = try JSONSerialization.data(withJSONObject: object)
        try data.write(to: directory.appending(path: "package.json"))
    }

    private func makeManager(
        root: URL?,
        defaults: UserDefaults? = nil,
        settings: CEWorkspaceSettingsData? = nil,
        discovery: TaskDiscovery? = nil
    ) throws -> TaskManager {
        TaskManager(
            workspaceSettings: settings ?? self.settings,
            workspaceURL: root,
            discovery: discovery,
            selectionDefaults: try defaults ?? makeDefaults(),
            settings: fixture.settingsStore
        )
    }

    @Test
    func withoutAWorkspaceThereIsNothingToDiscover() async throws {
        let manager = try makeManager(root: nil)

        await manager.refreshDiscoveredTasks()

        #expect(manager.discoveredSections.isEmpty)
        #expect(manager.runConfigurationSections.isEmpty)
        #expect(manager.availableTasks.isEmpty)
    }

    @Test
    func discoveredGroupsAreListedAfterTheUserTasks() async throws {
        try await withTempDir { directory in
            try writePackage(in: directory)
            settings.tasks = [CETask(name: "Build", command: "make")]
            let manager = try makeManager(root: directory)

            await manager.refreshDiscoveredTasks()

            let sections = manager.runConfigurationSections
            #expect(sections.map(\.title) == [RunConfigurationSection.workspaceTitle, "npm"])
            #expect(sections.map(\.isDiscovered) == [false, true])
            #expect(sections[1].subtitle == "package.json")
            #expect(sections[1].kind == .npm)
            #expect(manager.availableTasks.map(\.name) == ["Build", "npm run build", "npm run dev"])
            #expect(manager.availableTasks.last?.command == "npm run dev")
            #expect(manager.availableTasks.last?.source != CETask.workspaceSource)
        }
    }

    @Test
    func discoveredTaskIdentitiesAreStableAcrossScans() async throws {
        try await withTempDir { directory in
            try writePackage(in: directory)
            let first = try makeManager(root: directory)
            let second = try makeManager(root: directory)

            await first.refreshDiscoveredTasks()
            await second.refreshDiscoveredTasks()

            #expect(!first.availableTasks.isEmpty)
            #expect(first.availableTasks.map(\.id) == second.availableTasks.map(\.id))
        }
    }

    @Test
    func theScanRunsOffTheMainThread() async throws {
        try await withTempDir { directory in
            try writePackage(in: directory)
            let recorder = ThreadRecorder()
            let discovery = TaskDiscovery(rootURL: directory, scanProbe: { recorder.record() })
            let manager = try makeManager(root: directory, discovery: discovery)

            try await eventually { !manager.discoveredSections.isEmpty }

            #expect(!recorder.recorded.isEmpty)
            #expect(recorder.recorded.allSatisfy { !$0 })
        }
    }

    @Test
    func aDiscoveredTaskEqualToAUserTaskIsHidden() async throws {
        try await withTempDir { directory in
            try writePackage(in: directory, scripts: ["dev": "vite"])
            settings.tasks = [CETask(name: "mine", workingDirectory: ".", command: "npm run dev")]
            let manager = try makeManager(root: directory)

            await manager.refreshDiscoveredTasks()

            #expect(manager.availableTasks.map(\.name) == ["mine"])
            #expect(manager.runConfigurationSections.count == 1)
        }
    }

    @Test
    func savingADiscoveredTaskCopiesItIntoTheWorkspaceSettings() async throws {
        try await withTempDir { directory in
            try writePackage(in: directory, scripts: ["dev": "vite"])
            let manager = try makeManager(root: directory)
            await manager.refreshDiscoveredTasks()
            let discovered = try #require(manager.availableTasks.first)
            manager.selectedTaskID = discovered.id

            let saved = try #require(manager.saveDiscoveredTask(discovered))

            #expect(settings.tasks.map(\.id) == [saved.id])
            #expect(saved.source == CETask.workspaceSource)
            #expect(saved.name == discovered.name)
            #expect(saved.command == discovered.command)
            #expect(saved.workingDirectory == discovered.workingDirectory)
            #expect(saved.target == "My Mac")
            #expect(manager.selectedTaskID == saved.id)
            #expect(manager.availableTasks.map(\.id) == [saved.id])
            #expect(manager.saveDiscoveredTask(saved) == nil)
        }
    }

    @Test
    func savingADiscoveredTaskKeepsAnotherSelectionAndAvoidsNameClashes() async throws {
        try await withTempDir { directory in
            try writePackage(in: directory, scripts: ["dev": "vite", "lint": "eslint"])
            let existing = CETask(name: "npm run dev", command: "something else")
            settings.tasks = [existing]
            let manager = try makeManager(root: directory)
            await manager.refreshDiscoveredTasks()
            manager.selectedTaskID = existing.id
            let discovered = try #require(manager.availableTasks.first { $0.command == "npm run dev" })

            let saved = try #require(manager.saveDiscoveredTask(discovered))

            #expect(saved.name == "npm run dev (2)")
            #expect(manager.selectedTaskID == existing.id)
            #expect(settings.tasks.map(\.name) == ["npm run dev", "npm run dev (2)"])
        }
    }

    @Test
    func theSelectedConfigurationSurvivesARestart() async throws {
        try await withTempDir { directory in
            try writePackage(in: directory)
            let defaults = try makeDefaults()
            let first = try makeManager(root: directory, defaults: defaults)
            await first.refreshDiscoveredTasks()
            let chosen = try #require(first.availableTasks.first { $0.command == "npm run dev" })
            first.selectedTaskID = chosen.id

            let restartedSettings = try JSONDecoder().decode(CEWorkspaceSettingsData.self, from: Data("{}".utf8))
            restartedSettings.tasks = [CETask(name: "Build", command: "make")]
            let restarted = try makeManager(root: directory, defaults: defaults, settings: restartedSettings)
            try await eventually { restarted.selectedTaskID == chosen.id }

            #expect(restarted.selectedTask?.command == "npm run dev")
        }
    }

    @Test
    func aUserTaskSelectionSurvivesARestartToo() async throws {
        try await withTempDir { directory in
            let defaults = try makeDefaults()
            let kept = CETask(name: "Second", command: "true")
            settings.tasks = [CETask(name: "First", command: "true"), kept]
            let first = try makeManager(root: directory, defaults: defaults)
            first.selectedTaskID = kept.id

            let restartedSettings = try JSONDecoder().decode(CEWorkspaceSettingsData.self, from: Data("{}".utf8))
            restartedSettings.tasks = [CETask(name: "First", command: "true"), CETask(name: "Second", command: "true")]
            let restarted = try makeManager(root: directory, defaults: defaults, settings: restartedSettings)
            try await eventually { restarted.selectedTaskID == kept.id }

            #expect(restarted.selectedTask?.name == "Second")
        }
    }

    @Test
    func aVanishedPersistedSelectionFallsBackToTheFirstTask() async throws {
        try await withTempDir { directory in
            try writePackage(in: directory)
            let defaults = try makeDefaults()
            let first = try makeManager(root: directory, defaults: defaults)
            await first.refreshDiscoveredTasks()
            first.selectedTaskID = first.availableTasks.last?.id

            try FileManager.default.removeItem(at: directory.appending(path: "package.json"))
            let restartedSettings = try JSONDecoder().decode(CEWorkspaceSettingsData.self, from: Data("{}".utf8))
            let survivor = CETask(name: "Survivor", command: "true")
            restartedSettings.tasks = [survivor]
            let restarted = try makeManager(root: directory, defaults: defaults, settings: restartedSettings)
            await restarted.refreshDiscoveredTasks()

            #expect(restarted.selectedTaskID == survivor.id)
            #expect(restarted.selectedTask?.id == survivor.id)
        }
    }

    @Test
    func clearingTheSelectionForgetsThePersistedChoice() async throws {
        try await withTempDir { directory in
            try writePackage(in: directory)
            let defaults = try makeDefaults()
            let first = try makeManager(root: directory, defaults: defaults)
            await first.refreshDiscoveredTasks()
            first.selectedTaskID = first.availableTasks.last?.id
            first.selectedTaskID = nil

            let restarted = try makeManager(root: directory, defaults: defaults)
            await restarted.refreshDiscoveredTasks()

            #expect(restarted.selectedTaskID == restarted.availableTasks.first?.id)
            #expect(restarted.selectedTaskID != first.availableTasks.last?.id)
        }
    }

    @Test
    func aFallbackSelectionIsNeverWrittenToTheDefaults() async throws {
        try withTempDir { directory in
            let defaults = try makeDefaults()
            settings.tasks = [CETask(name: "Only", command: "true")]
            let manager = try makeManager(root: directory, defaults: defaults)

            manager.updateSelectedTaskID()

            #expect(manager.selectedTaskID == settings.tasks.first?.id)
            #expect(defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("dreamder.selectedTask.") }.isEmpty)
        }
    }

    @Test
    func theRunningStateFollowsTheActiveTasks() {
        let manager = TaskManager(workspaceSettings: settings, workspaceURL: nil, settings: fixture.settingsStore)
        #expect(!manager.hasRunningTasks)

        let task = fixture.makeTask(command: "true")
        let activeTask = CEActiveTask(task: task)
        manager.activeTasks[task.id] = activeTask
        #expect(!manager.hasRunningTasks)

        activeTask.updateTaskStatus(to: .running)
        #expect(manager.hasRunningTasks)
    }

    @Test
    func executeActiveTaskRunsADiscoveredTask() async throws {
        try await withTempDir { directory in
            try writePackage(in: directory, scripts: ["dev": "vite"])
            let manager = RunRecordingTaskManager(
                workspaceSettings: settings,
                workspaceURL: directory,
                discovery: nil,
                selectionDefaults: try makeDefaults(),
                settings: fixture.settingsStore
            )
            await manager.refreshDiscoveredTasks()
            let discovered = try #require(manager.availableTasks.first)
            manager.selectedTaskID = discovered.id

            manager.executeActiveTask()

            try await eventually { !manager.ranTasks.isEmpty }
            #expect(manager.ranTasks.map(\.id) == [discovered.id])
            #expect(manager.ranTasks.first?.command == "npm run dev")
        }
    }

    @Test
    func rerunLastTaskRestartsTheTaskThatRanLast() async throws {
        let manager = TaskManager(workspaceSettings: settings, workspaceURL: nil, settings: fixture.settingsStore)
        #expect(manager.rerunLastTask() == nil)

        let task = fixture.makeTask(command: "echo again-$((2+2))")
        await manager.runTask(task: task)
        #expect(manager.lastRunTask === task)
        let activeTask = try #require(manager.activeTasks[task.id])
        try await eventually { manager.taskStatus(taskID: task.id) == .finished }
        let firstRunID = activeTask.activeTaskID

        let rerun = try #require(manager.rerunLastTask())
        await rerun.value

        #expect(activeTask.activeTaskID != firstRunID)
        try await eventually { manager.taskStatus(taskID: task.id) == .finished }
    }
}
