import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct CEActiveTaskStartFailureTests {
    private static let stepTimeout = Duration.seconds(20)

    private let fixture: TasksCoverageFixture

    init() throws {
        fixture = try TasksCoverageFixture()
    }

    private func makeTaskWithoutAnyShell() -> (CEActiveTask, CEActiveTaskTerminalView) {
        let activeTask = CEActiveTask(task: fixture.makeTask(command: "true"), settings: fixture.settingsStore)
        let view = CEActiveTaskTerminalView(activeTask: activeTask)
        view.isExecutable = { _ in false }
        activeTask.output = view
        return (activeTask, view)
    }

    @Test
    func aTaskWithoutAnyExecutableShellFailsInsteadOfStayingRunning() {
        let (activeTask, view) = makeTaskWithoutAnyShell()

        activeTask.run(workspaceURL: nil)

        #expect(activeTask.status == .failed)
        #expect(!activeTask.isActive)
        #expect(view.runningPID() == nil)
        #expect(activeTask.output === view)
    }

    @Test
    func aTaskWhoseWorkingDirectoryIsMissingFailsInsteadOfStayingRunning() {
        let task = CETask(
            name: "Gone",
            workingDirectory: "gone-\(UUID().uuidString)",
            command: "true",
            environmentVariables: fixture.makeTask(command: "true").environmentVariables
        )
        let activeTask = CEActiveTask(task: task, settings: fixture.settingsStore)

        activeTask.run(workspaceURL: fixture.markersDirectory)

        #expect(activeTask.status == .failed)
        #expect(!activeTask.isActive)
        #expect(activeTask.output?.runningPID() == nil)
    }

    @Test
    func aTaskWhoseSpawnLeavesNoProcessFailsInsteadOfStayingRunning() {
        let activeTask = CEActiveTask(task: fixture.makeTask(command: "true"), settings: fixture.settingsStore)
        let view = CEActiveTaskTerminalView(activeTask: activeTask)
        view.spawnProcess = { _, _ in }
        activeTask.output = view

        activeTask.run(workspaceURL: nil, shell: .zsh)

        #expect(activeTask.status == .failed)
        #expect(!activeTask.isActive)
        #expect(view.runningPID() == nil)
    }

    @Test
    func aTaskWhoseShellCannotStartPostsTheFailureAndRemovesItsRunningNotification() async throws {
        let recorder = TasksCoverageNotificationRecorder()
        defer { recorder.stop() }
        let (activeTask, _) = makeTaskWithoutAnyShell()

        activeTask.run(workspaceURL: nil)

        try await eventually(timeout: Self.stepTimeout) {
            recorder.entries(for: activeTask.taskId).contains { $0.action == "deleteWithDelay" }
        }
        let actions = recorder.entries(for: activeTask.taskId).map(\.action)
        #expect(actions == ["createWithPriority", "update", "deleteWithDelay"])
        let update = recorder.entries(for: activeTask.taskId).first { $0.action == "update" }
        #expect(update?.title == "Failed Running Coverage Task")
    }

    @Test
    func runningAgainAfterAStartFailureFailsAgainWithoutLeavingARunningTask() {
        let (activeTask, _) = makeTaskWithoutAnyShell()
        activeTask.run(workspaceURL: nil)
        let firstRunID = activeTask.activeTaskID

        activeTask.run(workspaceURL: nil)

        #expect(activeTask.activeTaskID != firstRunID)
        #expect(activeTask.status == .failed)
        #expect(!activeTask.isActive)
    }

    @Test
    func theTaskManagerNeverKeepsATaskRunningWhenItsShellCannotStart() async throws {
        let settings = try JSONDecoder().decode(CEWorkspaceSettingsData.self, from: Data("{}".utf8))
        let manager = TaskManager(workspaceSettings: settings, workspaceURL: nil, settings: fixture.settingsStore)
        let (activeTask, _) = makeTaskWithoutAnyShell()
        manager.activeTasks[activeTask.task.id] = activeTask

        await manager.runTask(task: activeTask.task)

        #expect(manager.taskStatus(taskID: activeTask.task.id) == .failed)
        #expect(!manager.hasActiveTasks)
        #expect(!manager.hasRunningTasks)
    }
}
