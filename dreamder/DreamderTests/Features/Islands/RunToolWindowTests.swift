import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct RunToolWindowTests {
    private func makeActiveTask(_ name: String, status: CETaskStatus? = nil) -> CEActiveTask {
        let activeTask = CEActiveTask(task: CETask(name: name, command: "true"))
        if let status {
            activeTask.updateTaskStatus(to: status)
        }
        return activeTask
    }

    private func makeTaskManager(_ workspace: WorkspaceDocument) throws -> TaskManager {
        try #require(workspace.taskManager)
    }

    @Test
    func emptyStateOffersTheRunnableTaskAndFallsBackToTheFirstOne() async throws {
        try await withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let manager = try makeTaskManager(workspace)
            let first = CETask(name: "first", command: "true")
            let second = CETask(name: "second", command: "true")

            let hosted = try HostedViewFixture.hostInWorkspace(workspace) { RunToolWindow() }
            defer { hosted.close() }
            try await hosted.settle(.milliseconds(100))
            #expect(hosted.renders())
            let withoutTasks = hosted.snapshot()

            manager.workspaceSettings.tasks = [first, second]
            manager.selectedTaskID = second.id
            try await hosted.settle(.milliseconds(100))
            let withSelectedTask = hosted.snapshot()
            #expect(HostedView.pixelsDiffer(withoutTasks, withSelectedTask))

            manager.selectedTaskID = UUID()
            try await hosted.settle(.milliseconds(100))
            #expect(hosted.renders())
        }
    }

    @Test
    func tabsFollowTheActiveTasksAndKeepTheShownOutputValid() async throws {
        try await withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let manager = try makeTaskManager(workspace)
            let unnamed = makeActiveTask("", status: .notRunning)
            let build = makeActiveTask("build 10", status: .running)
            let lint = makeActiveTask("build 2", status: .stopped)

            let hosted = try HostedViewFixture.hostInWorkspace(workspace) { RunToolWindow() }
            defer { hosted.close() }

            manager.activeTasks = [build.task.id: build, unnamed.task.id: unnamed]
            try await eventually { manager.taskShowingOutput == unnamed.task.id }
            try await hosted.settle(.milliseconds(100))
            #expect(hosted.renders())

            manager.activeTasks[lint.task.id] = lint
            try await hosted.settle(.milliseconds(100))
            #expect(manager.taskShowingOutput == unnamed.task.id)

            manager.taskShowingOutput = UUID()
            try await hosted.settle(.milliseconds(100))
            #expect(hosted.renders())

            manager.taskShowingOutput = lint.task.id
            try await hosted.settle(.milliseconds(100))
            #expect(hosted.renders())

            manager.activeTasks.removeValue(forKey: lint.task.id)
            try await eventually { manager.taskShowingOutput == unnamed.task.id }

            for status in [CETaskStatus.finished, .failed, .running, .stopped] {
                unnamed.updateTaskStatus(to: status)
                try await hosted.settle(.milliseconds(100))
                #expect(hosted.renders())
            }

            manager.activeTasks.removeAll()
            try await eventually { manager.taskShowingOutput == nil }
            try await hosted.settle(.milliseconds(100))
            #expect(hosted.renders())
        }
    }

    @Test
    func rendersTheTerminalOutputOnlyOnceTheTaskHasOutput() async throws {
        try await withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let manager = try makeTaskManager(workspace)
            let activeTask = makeActiveTask("output", status: .finished)
            manager.activeTasks[activeTask.task.id] = activeTask

            let hosted = try HostedViewFixture.hostInWorkspace(workspace) { RunToolWindow() }
            defer { hosted.close() }
            try await hosted.settle(.milliseconds(100))

            let standalone = HostedViewFixture.host { TaskOutputView(activeTask: activeTask) }
            try await standalone.settle(.milliseconds(100))
            #expect(standalone.views(of: CEActiveTaskTerminalView.self).isEmpty)
            standalone.close()

            activeTask.workspaceURL = dir
            activeTask.output = CEActiveTaskTerminalView(activeTask: activeTask)
            try await eventually(timeout: .seconds(30)) {
                hosted.layout()
                return hosted.views(of: CEActiveTaskTerminalView.self).count == 1
            }
            #expect(hosted.renders())
        }
    }

    @Test
    func selectCloseStopAndClearActOnTheGivenTask() async throws {
        try withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let manager = try makeTaskManager(workspace)
            let actions = RunToolWindowActions(taskManager: manager)
            let first = makeActiveTask("first", status: .running)
            let second = makeActiveTask("second", status: .running)
            manager.activeTasks[first.task.id] = first
            manager.activeTasks[second.task.id] = second

            actions.select(second)()
            #expect(manager.taskShowingOutput == second.task.id)

            actions.stop(first)()
            #expect(manager.activeTasks.count == 2)

            second.output = CEActiveTaskTerminalView(activeTask: second)
            actions.clear(second)()
            #expect(second.output?.getBufferAsString().isEmpty == true)

            actions.close(first)()
            #expect(manager.activeTasks[first.task.id] == nil)
            #expect(manager.activeTasks[second.task.id] != nil)
        }
    }

    @Test
    func runStartsTheTaskThroughTheTaskManager() async throws {
        try await withTempDir { dir in
            let zdotdir = dir.appending(path: "zdotdir", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: zdotdir, withIntermediateDirectories: true)
            for name in [".zshenv", ".zprofile", ".zshrc", ".zlogin"] {
                try "".write(to: zdotdir.appending(path: name), atomically: true, encoding: .utf8)
            }
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let leases = PooledDefaultsLeases()
            let trust = WorkspaceTrust(defaults: try leases.make(), confirm: { _ in true })
            let manager = TaskManager(
                workspaceSettings: try makeTaskManager(workspace).workspaceSettings,
                workspaceURL: dir,
                selectionDefaults: try leases.make(),
                trust: trust
            )
            let task = CETask(
                name: "echo",
                command: "echo run-window-marker",
                environmentVariables: [
                    CETask.EnvironmentVariable(key: "ZDOTDIR", value: zdotdir.path(percentEncoded: false))
                ]
            )

            RunToolWindowActions(taskManager: manager).run(task)()

            try await eventually { manager.activeTasks[task.id]?.status == .finished }
            manager.deleteTask(taskID: task.id)
            #expect(manager.activeTasks[task.id] == nil)
        }
    }
}
