import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct TaskManagerCoverageTests {
    private static let stepTimeout = Duration.seconds(20)
    private let fixture: TasksCoverageFixture
    private let settings: CEWorkspaceSettingsData
    private let manager: TaskManager

    init() throws {
        let fixture = try TasksCoverageFixture()
        self.fixture = fixture
        settings = try JSONDecoder().decode(CEWorkspaceSettingsData.self, from: Data("{}".utf8))
        manager = TaskManager(workspaceSettings: settings, workspaceURL: nil, settings: fixture.settingsStore)
    }

    @Test
    func taskStatusDefaultsToNotRunningAndFollowsTheActiveTask() async {
        let task = fixture.makeTask(command: "true")
        #expect(manager.taskStatus(taskID: task.id) == .notRunning)

        let activeTask = CEActiveTask(task: task)
        manager.activeTasks[task.id] = activeTask
        #expect(manager.taskStatus(taskID: task.id) == .notRunning)

        activeTask.updateTaskStatus(to: .running)
        #expect(manager.taskStatus(taskID: task.id) == .running)
        activeTask.updateTaskStatus(to: .failed)
        #expect(manager.taskStatus(taskID: task.id) == .failed)
    }

    @Test
    func selectedTaskResolvesTheExplicitSelectionOnly() {
        let first = fixture.makeTask(name: "First", command: "true")
        let second = fixture.makeTask(name: "Second", command: "true")
        settings.tasks = [first, second]

        #expect(manager.selectedTask?.id == first.id)

        manager.selectedTaskID = second.id
        #expect(manager.selectedTask?.id == second.id)

        manager.selectedTaskID = UUID()
        #expect(manager.selectedTask == nil)
    }

    @Test
    func updateSelectedTaskIDKeepsAValidSelectionAndReplacesAStaleOne() {
        let first = fixture.makeTask(name: "First", command: "true")
        let second = fixture.makeTask(name: "Second", command: "true")
        settings.tasks = [first, second]
        manager.selectedTaskID = second.id

        manager.updateSelectedTaskID()
        #expect(manager.selectedTaskID == second.id)

        manager.selectedTaskID = UUID()
        manager.updateSelectedTaskID()
        #expect(manager.selectedTaskID == first.id)
    }

    @Test
    func changingTheWorkspaceTasksKeepsTheSelectionValid() async throws {
        let first = fixture.makeTask(name: "First", command: "true")
        settings.tasks = [first]
        try await eventually { manager.selectedTaskID == first.id }

        settings.tasks = []
        try await eventually { manager.selectedTaskID == nil }
    }

    @Test
    func executeActiveTaskWithoutAnySelectionRunsNothing() async throws {
        settings.tasks = [fixture.makeTask(command: "true")]

        manager.executeActiveTask()
        try await Task.sleep(for: .milliseconds(200))

        #expect(manager.activeTasks.isEmpty)
    }

    @Test
    func runTaskStartsATaskAndRegistersIt() async throws {
        let task = fixture.makeTask(command: "echo registered-$((1+1))")

        await manager.runTask(task: task)

        let activeTask = try #require(manager.activeTasks[task.id])
        try await eventually { manager.taskStatus(taskID: task.id) == .finished }
        let output = try #require(activeTask.output)
        try await fixture.waitForOutput(output, containing: "registered-2")
    }

    @Test
    func runTaskRestartsATaskThatIsStillRunning() async throws {
        let task = fixture.makeSignalTask()
        await manager.runTask(task: task)
        let activeTask = try #require(manager.activeTasks[task.id])
        let output = try #require(activeTask.output)
        try await fixture.waitUntilReady(output, timeout: Self.stepTimeout)
        let firstRunID = activeTask.activeTaskID

        await manager.runTask(task: task)

        #expect(manager.activeTasks[task.id] === activeTask)
        #expect(activeTask.activeTaskID != firstRunID)
        try await fixture.waitUntilReady(output, occurrences: 2, timeout: Self.stepTimeout)
        manager.terminateTask(taskID: task.id)
        try await eventually(timeout: Self.stepTimeout) { manager.taskStatus(taskID: task.id) == .notRunning }
    }

    @Test
    func terminateActiveTaskNeedsASelectedTask() async throws {
        let task = fixture.makeSignalTask()
        await manager.runTask(task: task)
        let output = try #require(manager.activeTasks[task.id]?.output)
        try await fixture.waitUntilReady(output, timeout: Self.stepTimeout)

        manager.terminateActiveTask()
        try await Task.sleep(for: .milliseconds(300))
        #expect(manager.taskStatus(taskID: task.id) == .running)

        manager.selectedTaskID = task.id
        manager.terminateActiveTask()
        try await eventually(timeout: Self.stepTimeout) { manager.taskStatus(taskID: task.id) == .notRunning }
        try await fixture.waitForOutput(output, containing: "Signal Task cancelled.", timeout: Self.stepTimeout)
    }

    @Test
    func suspendAndResumeTaskPauseAndContinueTheRunningTask() async throws {
        let task = fixture.makeSignalTask()
        await manager.runTask(task: task)
        let activeTask = try #require(manager.activeTasks[task.id])
        let output = try #require(activeTask.output)
        try await fixture.waitUntilReady(output)
        let pid = try #require(output.runningPID())

        manager.suspendTask(taskID: UUID())
        manager.resumeTask(taskID: UUID())
        #expect(manager.taskStatus(taskID: task.id) == .running)

        manager.suspendTask(taskID: task.id)
        #expect(manager.taskStatus(taskID: task.id) == .stopped)
        try await eventually { TasksCoverageProcessProbe.isStopped(pid) }

        manager.resumeTask(taskID: task.id)
        #expect(manager.taskStatus(taskID: task.id) == .running)
        try await eventually { !TasksCoverageProcessProbe.isStopped(pid) }

        manager.terminateTask(taskID: task.id)
        try await eventually(timeout: Self.stepTimeout) { manager.taskStatus(taskID: task.id) == .notRunning }
    }

    @Test
    func interruptTaskSendsSigintToTheTaskOnly() async throws {
        let task = fixture.makeSignalTask()
        await manager.runTask(task: task)
        let output = try #require(manager.activeTasks[task.id]?.output)
        try await fixture.waitUntilReady(output)

        manager.interruptTask(taskID: UUID())
        manager.terminateTask(taskID: UUID())
        try await Task.sleep(for: .milliseconds(200))
        #expect(manager.taskStatus(taskID: task.id) == .running)

        manager.interruptTask(taskID: task.id)
        try await eventually { manager.taskStatus(taskID: task.id) == .finished }
        try await fixture.waitForOutput(output, containing: TasksCoverageFixture.interruptMarker)
    }

    @Test
    func stopAllTasksInterruptsEveryActiveTask() async throws {
        let task = fixture.makeSignalTask()
        await manager.runTask(task: task)
        let output = try #require(manager.activeTasks[task.id]?.output)
        try await fixture.waitUntilReady(output)

        manager.stopAllTasks()

        try await eventually { manager.taskStatus(taskID: task.id) == .finished }
        try await fixture.waitForOutput(output, containing: TasksCoverageFixture.interruptMarker)
    }

    @Test
    func deleteTaskTerminatesTheTaskAndForgetsIt() async throws {
        let task = fixture.makeSignalTask()
        await manager.runTask(task: task)
        let activeTask = try #require(manager.activeTasks[task.id])
        let output = try #require(activeTask.output)
        try await fixture.waitUntilReady(output, timeout: Self.stepTimeout)
        let pid = try #require(output.runningPID())

        let termination = manager.deleteTask(taskID: task.id)

        #expect(manager.activeTasks[task.id] == nil)
        await termination?.value
        try await eventually(timeout: Self.stepTimeout) { activeTask.status == .notRunning }
        try await eventually(timeout: Self.stepTimeout) { TasksCoverageProcessProbe.isGone(pid) }
    }
}
