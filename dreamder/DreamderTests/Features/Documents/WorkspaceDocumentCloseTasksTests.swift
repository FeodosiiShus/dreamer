import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct WorkspaceDocumentCloseTasksTests {
    private static let stepTimeout = Duration.seconds(20)

    private let fixture: TasksCoverageFixture

    init() throws {
        fixture = try TasksCoverageFixture()
    }

    private func makeManager() throws -> TaskManager {
        let settings = try JSONDecoder().decode(CEWorkspaceSettingsData.self, from: Data("{}".utf8))
        return TaskManager(workspaceSettings: settings, workspaceURL: nil, settings: fixture.settingsStore)
    }

    @Test
    func closingAWorkspaceTerminatesItsRunningTasks() async throws {
        let workspace = WorkspaceDocument()
        let manager = try makeManager()
        let task = fixture.makeTask(command: "true")
        let scripted = ScriptedActiveTask(task: task, settings: fixture.settingsStore)
        scripted.updateTaskStatus(to: .running)
        scripted.terminationGate.open()
        manager.activeTasks[task.id] = scripted
        workspace.taskManager = manager

        workspace.close()

        #expect(workspace.taskManager == nil)
        try await eventually(timeout: Self.stepTimeout) { scripted.terminateAndWaitCount == 1 }
        try await eventually(timeout: Self.stepTimeout) { !scripted.isActive }
    }

    @Test
    func closingAWorkspaceLeavesNoShellBehindForATaskThatIgnoresGentleSignals() async throws {
        let workspace = WorkspaceDocument()
        let manager = try makeManager()
        let command = """
        trap '' HUP TERM INT; m=ready-$((40+2)); echo $m >> "$\(TasksCoverageFixture.markersDirectoryVariable)/\
        \(TasksCoverageFixture.readyFile)"; echo $m; \
        i=0; while [ $i -lt 600 ]; do sleep 0.1; i=$((i+1)); done
        """
        let task = fixture.makeTask(command: command)
        let activeTask = CEActiveTask(task: task, settings: fixture.settingsStore)
        activeTask.terminationGrace = .milliseconds(150)
        manager.activeTasks[task.id] = activeTask
        workspace.taskManager = manager
        activeTask.run(workspaceURL: nil, shell: .zsh)
        try await fixture.waitUntilSignalTaskIsReady(timeout: Self.stepTimeout)
        let output = try #require(activeTask.output)
        let shell = try #require(output.runningPID())
        defer { kill(shell, SIGKILL) }

        workspace.close()

        try await eventually(timeout: Self.stepTimeout) { activeTask.status == .notRunning }
        try await eventually(timeout: Self.stepTimeout) { TasksCoverageProcessProbe.isGone(shell) }
    }

    @Test
    func closingAWorkspaceWithoutATaskManagerLeavesNoTaskManager() {
        let workspace = WorkspaceDocument()
        #expect(workspace.taskManager == nil)

        workspace.close()

        #expect(workspace.taskManager == nil)
    }

    @Test
    func closingAWorkspaceLeavesNoPendingEscalationForTasksWithoutAProcess() async throws {
        let workspace = WorkspaceDocument()
        var manager: TaskManager? = try makeManager()
        let tracker = try #require(manager?.terminations)
        let task = fixture.makeTask(command: "true")
        let activeTask = CEActiveTask(task: task, settings: fixture.settingsStore)
        activeTask.updateTaskStatus(to: .running)
        activeTask.sleep = { _ in try await Task.sleep(for: .seconds(3600)) }
        manager?.activeTasks[task.id] = activeTask
        workspace.taskManager = manager
        manager = nil

        workspace.close()

        #expect(workspace.taskManager == nil)
        try await eventually(timeout: Self.stepTimeout) { tracker.pendingCount == 0 }
    }
}
