import Foundation
import Synchronization
import Testing
@testable import Dreamder

private final class SleepProbe: Sendable {
    private let count = Mutex(0)

    var calls: Int {
        count.withLock { $0 }
    }

    func record() {
        count.withLock { $0 += 1 }
    }
}

@MainActor
@Suite(.serialized, .uiGate)
struct TaskEscalationLifetimeTests {
    private static let stepTimeout = Duration.seconds(20)
    private static let promptTimeout = Duration.seconds(10)

    private let fixture: TasksCoverageFixture

    init() throws {
        fixture = try TasksCoverageFixture()
    }

    private func makeManager() throws -> TaskManager {
        let settings = try JSONDecoder().decode(CEWorkspaceSettingsData.self, from: Data("{}".utf8))
        return TaskManager(workspaceSettings: settings, workspaceURL: nil, settings: fixture.settingsStore)
    }

    private func makeRunningTaskWithoutProcess(
        in manager: TaskManager,
        probe: SleepProbe = SleepProbe()
    ) -> CEActiveTask {
        let task = fixture.makeTask(command: "true")
        let activeTask = CEActiveTask(task: task, settings: fixture.settingsStore)
        activeTask.updateTaskStatus(to: .running)
        activeTask.sleep = { _ in
            probe.record()
            try await Task.sleep(for: .seconds(3600))
        }
        manager.activeTasks[task.id] = activeTask
        return activeTask
    }

    @Test
    func releasingTheManagerCancelsEscalationsOfTasksWithoutAProcess() async throws {
        var manager: TaskManager? = try makeManager()
        weak let weakManager = manager
        let tracker = try #require(manager?.terminations)
        let probe = SleepProbe()
        let activeTask = try #require(manager.map { makeRunningTaskWithoutProcess(in: $0, probe: probe) })
        let escalation = try #require(manager?.terminateTask(taskID: activeTask.task.id))
        let finished = CompletionFlag()
        let waiter = Task {
            await escalation.value
            finished.set()
        }
        defer { waiter.cancel() }
        try await eventually(timeout: Self.stepTimeout) { probe.calls >= 1 }
        #expect(tracker.pendingCount == 1)
        #expect(!finished.isSet)

        manager = nil

        try await eventually(timeout: Self.promptTimeout) { finished.isSet }
        #expect(weakManager == nil)
        #expect(tracker.pendingCount == 0)
        #expect(activeTask.status == .running)
    }

    @Test
    func releasingTheManagerKeepsEscalatingForTasksWithALiveProcess() async throws {
        var manager: TaskManager? = try makeManager()
        let tracker = try #require(manager?.terminations)
        let command = """
        trap '' HUP TERM INT; m=ready-$((40+2)); echo $m >> "$\(TasksCoverageFixture.markersDirectoryVariable)/\
        \(TasksCoverageFixture.readyFile)"; echo $m; \
        i=0; while [ $i -lt 600 ]; do sleep 0.1; i=$((i+1)); done
        """
        let task = fixture.makeTask(command: command)
        let activeTask = CEActiveTask(task: task, settings: fixture.settingsStore)
        activeTask.terminationGrace = .milliseconds(150)
        manager?.activeTasks[task.id] = activeTask
        activeTask.run(workspaceURL: nil, shell: .zsh)
        try await fixture.waitUntilSignalTaskIsReady(timeout: Self.stepTimeout)
        let output = try #require(activeTask.output)
        let shell = try #require(output.runningPID())
        defer { kill(shell, SIGKILL) }
        let escalation = try #require(manager?.terminateTask(taskID: task.id))

        manager = nil
        await escalation.value

        try await eventually(timeout: Self.stepTimeout) { activeTask.status == .notRunning }
        try await eventually(timeout: Self.stepTimeout) { TasksCoverageProcessProbe.isGone(shell) }
        #expect(tracker.pendingCount == 0)
    }

    @Test
    func aFinishedEscalationIsForgotten() async throws {
        let manager = try makeManager()
        let activeTask = makeRunningTaskWithoutProcess(in: manager)
        activeTask.sleep = { _ in }

        let escalation = try #require(manager.terminateTask(taskID: activeTask.task.id))
        await escalation.value

        #expect(manager.terminations.pendingCount == 0)
    }

    @Test
    func terminatingEveryTaskAndReleasingTheManagerLeavesNoPendingEscalation() async throws {
        var manager: TaskManager? = try makeManager()
        let tracker = try #require(manager?.terminations)
        _ = try #require(manager.map { makeRunningTaskWithoutProcess(in: $0) })
        let all = try #require(manager?.terminateAllTasks())
        let finished = CompletionFlag()
        let waiter = Task {
            await all.value
            finished.set()
        }
        defer { waiter.cancel() }
        #expect(tracker.pendingCount == 1)

        manager = nil

        try await eventually(timeout: Self.promptTimeout) { finished.isSet }
        #expect(tracker.pendingCount == 0)
    }
}
