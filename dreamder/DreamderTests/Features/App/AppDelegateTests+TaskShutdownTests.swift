import AppKit
import Foundation
import Testing
@testable import Dreamder

extension AppDelegateTests {
    @MainActor
    final class ReplySnapshot {
        private(set) var statuses: [CETaskStatus] = []

        func record(_ status: CETaskStatus) {
            statuses.append(status)
        }
    }

    private static let taskStepTimeout = Duration.seconds(20)

    private static let ignoringEverythingCommand = """
    trap '' HUP TERM INT; m=ready-$((40+2)); echo $m >> "$\(TasksCoverageFixture.markersDirectoryVariable)/\
    \(TasksCoverageFixture.readyFile)"; echo $m; \
    i=0; while [ $i -lt 600 ]; do sleep 0.1; i=$((i+1)); done
    """

    private struct RunningWorkspace {
        let workspace: WorkspaceDocument
        let manager: TaskManager
        let activeTask: CEActiveTask
        let shell: pid_t
    }

    private func startWorkspaceTask(
        _ fixture: TasksCoverageFixture,
        command: String,
        grace: Duration = .milliseconds(150)
    ) async throws -> RunningWorkspace {
        let workspace = WorkspaceDocument()
        let settings = try JSONDecoder().decode(CEWorkspaceSettingsData.self, from: Data("{}".utf8))
        let manager = TaskManager(workspaceSettings: settings, workspaceURL: nil, settings: fixture.settingsStore)
        let task = fixture.makeTask(command: command)
        let activeTask = CEActiveTask(task: task, settings: fixture.settingsStore)
        activeTask.terminationGrace = grace
        manager.activeTasks[task.id] = activeTask
        workspace.taskManager = manager
        activeTask.run(workspaceURL: nil, shell: .zsh)
        try await fixture.waitUntilSignalTaskIsReady(timeout: Self.taskStepTimeout)
        let output = try #require(activeTask.output)
        let shell = try #require(output.runningPID())
        return RunningWorkspace(workspace: workspace, manager: manager, activeTask: activeTask, shell: shell)
    }

    @Test
    func quittingWithUnsavedDocumentsStopsTheTasksOfTheClosedWorkspacesBeforeReplying() async throws {
        let fixture = try TasksCoverageFixture()
        let harness = try TerminationHarness()
        defer { harness.tearDown() }
        let running = try await startWorkspaceTask(fixture, command: Self.ignoringEverythingCommand)
        defer { kill(running.shell, SIGKILL) }
        running.manager.shutdownTimeout = .seconds(10)
        let snapshot = ReplySnapshot()
        let recorder = harness.recorder
        let activeTask = running.activeTask
        harness.delegate.replyToTerminate = { reply in
            snapshot.record(activeTask.status)
            recorder.record(reply: reply)
        }
        harness.controller.closesDocumentsOnCloseAll = true
        harness.controller.stubbedDocuments = [running.workspace, EditedDocument()]

        let reply = harness.delegate.applicationShouldTerminate(NSApplication.shared)

        #expect(reply == .terminateLater)
        try await eventually(timeout: Self.taskStepTimeout) { recorder.replies == [true] }
        #expect(snapshot.statuses == [.notRunning])
        try await eventually(timeout: Self.taskStepTimeout) { TasksCoverageProcessProbe.isGone(running.shell) }
        try await eventually(timeout: Self.taskStepTimeout) { harness.recorder.notifications.count >= 3 }
        #expect(harness.recorder.notifications.first == "appdelegate.terminate_tasks:create")
    }

    @Test
    func cleanTerminationInterruptsCooperativeTasksAndRepliesAfterTheyExited() async throws {
        let fixture = try TasksCoverageFixture()
        let harness = try TerminationHarness()
        defer { harness.tearDown() }
        let running = try await startWorkspaceTask(fixture, command: TasksCoverageFixture.signalLoopCommand)
        defer { kill(running.shell, SIGKILL) }
        running.manager.shutdownTimeout = Self.taskStepTimeout
        let snapshot = ReplySnapshot()
        let recorder = harness.recorder
        let activeTask = running.activeTask
        harness.delegate.replyToTerminate = { reply in
            snapshot.record(activeTask.status)
            recorder.record(reply: reply)
        }
        harness.controller.stubbedDocuments = [running.workspace]

        _ = harness.delegate.applicationShouldTerminate(NSApplication.shared)

        try await eventually(timeout: Self.taskStepTimeout) { recorder.replies == [true] }
        #expect(snapshot.statuses == [.finished])
        #expect(fixture.markerFileContents(TasksCoverageFixture.interruptFile).contains(
            TasksCoverageFixture.interruptMarker
        ))
    }

    @Test
    func cleanTerminationKillsTasksThatIgnoreTheInterruptWhenTheDeadlinePasses() async throws {
        let fixture = try TasksCoverageFixture()
        let harness = try TerminationHarness()
        defer { harness.tearDown() }
        let running = try await startWorkspaceTask(fixture, command: Self.ignoringEverythingCommand)
        defer { kill(running.shell, SIGKILL) }
        running.manager.shutdownTimeout = .milliseconds(300)
        harness.controller.stubbedDocuments = [running.workspace]

        _ = harness.delegate.applicationShouldTerminate(NSApplication.shared)

        try await eventually(timeout: Self.taskStepTimeout) { harness.recorder.replies == [true] }
        try await eventually(timeout: Self.taskStepTimeout) { TasksCoverageProcessProbe.isGone(running.shell) }
        try await eventually(timeout: Self.taskStepTimeout) { running.activeTask.status == .notRunning }
    }

    @Test
    func theCloseAllCallbackWithoutContextRepliesAfterStoppingNothing() async throws {
        let harness = try TerminationHarness()
        defer { harness.tearDown() }

        harness.delegate.documentController(NSDocumentController.shared, didCloseAll: true, contextInfo: nil)

        try await eventually(timeout: Self.taskStepTimeout) {
            harness.recorder.replies == [true] && harness.recorder.notifications.count >= 2
        }
        #expect(harness.recorder.notifications == [
            "appdelegate.terminate_tasks:delete",
            "appdelegate.terminate_language_servers:delete"
        ])
    }
}
