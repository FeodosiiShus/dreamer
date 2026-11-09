import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct TaskManagerRunSerializationTests {
    private static let stepTimeout = Duration.seconds(20)

    private let fixture: TasksCoverageFixture
    private let manager: TaskManager

    init() throws {
        let fixture = try TasksCoverageFixture()
        self.fixture = fixture
        let settings = try JSONDecoder().decode(CEWorkspaceSettingsData.self, from: Data("{}".utf8))
        manager = TaskManager(workspaceSettings: settings, workspaceURL: nil, settings: fixture.settingsStore)
    }

    private func registerRunningTask(named name: String) -> (CETask, ScriptedActiveTask) {
        let task = fixture.makeTask(name: name, command: "true")
        let scripted = ScriptedActiveTask(task: task, settings: fixture.settingsStore)
        scripted.updateTaskStatus(to: .running)
        manager.activeTasks[task.id] = scripted
        return (task, scripted)
    }

    @Test
    func overlappingRunsOfOneRunningTaskRestartItOnce() async throws {
        let (task, scripted) = registerRunningTask(named: "Overlap")

        let first = Task { await manager.runTask(task: task) }
        let second = Task { await manager.runTask(task: task) }
        try await eventually(timeout: Self.stepTimeout) { scripted.terminateAndWaitCount >= 1 }
        #expect(scripted.runCount == 0)
        scripted.terminationGate.open()
        await first.value
        await second.value

        #expect(scripted.peakConcurrentTerminations == 1)
        #expect(scripted.runCount == scripted.terminateAndWaitCount)
        #expect(manager.activeTasks[task.id] === scripted)
    }

    @Test
    func aRunRequestedAfterTheRestartFinishedRestartsTheTaskAgain() async throws {
        let (task, scripted) = registerRunningTask(named: "Sequential")
        scripted.terminationGate.open()

        await manager.runTask(task: task)
        scripted.updateTaskStatus(to: .running)
        await manager.runTask(task: task)

        #expect(scripted.terminateAndWaitCount == 2)
        #expect(scripted.runCount == 2)
    }

    @Test
    func deletingATaskWhileItRestartsNeverRevivesIt() async throws {
        let (task, scripted) = registerRunningTask(named: "Deleted")

        let restart = Task { await manager.runTask(task: task) }
        try await eventually(timeout: Self.stepTimeout) { scripted.terminateAndWaitCount == 1 }
        let termination = manager.deleteTask(taskID: task.id)
        scripted.terminationGate.open()
        await restart.value
        await termination?.value

        #expect(scripted.runCount == 0)
        #expect(!scripted.isActive)
        #expect(manager.activeTasks[task.id] == nil)
    }

    @Test
    func aSlowRestartDoesNotBlockTheRestartOfAnotherTask() async throws {
        let (slowTask, slow) = registerRunningTask(named: "Slow")
        let (quickTask, quick) = registerRunningTask(named: "Quick")
        quick.terminationGate.open()

        let slowRestart = Task { await manager.runTask(task: slowTask) }
        try await eventually(timeout: Self.stepTimeout) { slow.terminateAndWaitCount == 1 }
        await manager.runTask(task: quickTask)

        #expect(quick.runCount == 1)
        #expect(slow.runCount == 0)
        slow.terminationGate.open()
        await slowRestart.value
        #expect(slow.runCount == 1)
    }

    @Test
    func rerunLastTaskJoinsTheRestartThatIsAlreadyRunning() async throws {
        let (task, scripted) = registerRunningTask(named: "Rerun")

        manager.lastRunTask = task
        let restart = Task { await manager.runTask(task: task) }
        let rerun = try #require(manager.rerunLastTask())
        try await eventually(timeout: Self.stepTimeout) { scripted.terminateAndWaitCount >= 1 }
        #expect(scripted.runCount == 0)
        scripted.terminationGate.open()
        await restart.value
        await rerun.value

        #expect(scripted.peakConcurrentTerminations == 1)
        #expect(scripted.runCount == scripted.terminateAndWaitCount)
    }
}
