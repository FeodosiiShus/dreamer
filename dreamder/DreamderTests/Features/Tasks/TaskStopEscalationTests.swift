import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct TaskStopEscalationTests {
    private static let stepTimeout = Duration.seconds(20)
    private static let continuedFile = "continued"
    private static let escalationGrace = Duration.milliseconds(150)

    private static let ignoringEverythingCommand = """
    trap '' HUP TERM INT; m=ready-$((40+2)); echo $m >> "$\(TasksCoverageFixture.markersDirectoryVariable)/\
    \(TasksCoverageFixture.readyFile)"; echo $m; \
    i=0; while [ $i -lt 600 ]; do sleep 0.1; i=$((i+1)); done
    """

    private static let continuingCommand = """
    sleep 600 & echo child-pid-$!-end; wait; \
    echo continued > "$\(TasksCoverageFixture.markersDirectoryVariable)/\(continuedFile)"
    """

    private let fixture: TasksCoverageFixture
    private let manager: TaskManager

    init() throws {
        let fixture = try TasksCoverageFixture()
        self.fixture = fixture
        let settings = try JSONDecoder().decode(CEWorkspaceSettingsData.self, from: Data("{}".utf8))
        manager = TaskManager(workspaceSettings: settings, workspaceURL: nil, settings: fixture.settingsStore)
    }

    private func start(_ task: CETask, shell: Shell = .zsh) -> CEActiveTask {
        let activeTask = CEActiveTask(task: task, settings: fixture.settingsStore)
        activeTask.terminationGrace = Self.escalationGrace
        manager.activeTasks[task.id] = activeTask
        activeTask.run(workspaceURL: nil, shell: shell)
        return activeTask
    }

    private func announcedChild(of activeTask: CEActiveTask) async throws -> pid_t {
        let output = try #require(activeTask.output)
        try await eventually(timeout: Self.stepTimeout) {
            TasksCoverageProcessProbe.announcedPID(in: output.getBufferAsString()) != nil
        }
        return try #require(TasksCoverageProcessProbe.announcedPID(in: output.getBufferAsString()))
    }

    @Test(arguments: [Shell.zsh, Shell.bash])
    func stopEndsAShellTaskBeforeItsNextCommandRuns(_ shell: Shell) async throws {
        let task = fixture.makeTask(command: Self.continuingCommand)
        let activeTask = start(task, shell: shell)
        let child = try await announcedChild(of: activeTask)
        defer { kill(child, SIGKILL) }

        let termination = try #require(manager.terminateTask(taskID: task.id))
        await termination.value

        try await eventually(timeout: Self.stepTimeout) { !activeTask.isActive }
        try await eventually(timeout: Self.stepTimeout) { TasksCoverageProcessProbe.isGone(child) }
        #expect(fixture.markerFileContents(Self.continuedFile).isEmpty)
        #expect(activeTask.status == .notRunning)
    }

    @Test
    func stopEscalatesToKillWhenTheShellIgnoresEveryGentleSignal() async throws {
        let task = fixture.makeTask(command: Self.ignoringEverythingCommand)
        let activeTask = start(task)
        try await fixture.waitUntilSignalTaskIsReady(timeout: Self.stepTimeout)
        let output = try #require(activeTask.output)
        let shell = try #require(output.runningPID())
        defer { kill(shell, SIGKILL) }

        let termination = try #require(manager.terminateTask(taskID: task.id))
        await termination.value

        try await eventually(timeout: Self.stepTimeout) { activeTask.status == .notRunning }
        try await eventually(timeout: Self.stepTimeout) { TasksCoverageProcessProbe.isGone(shell) }
    }

    @Test
    func deleteEndsATaskThatIgnoresEveryGentleSignalAndLeavesNoShellBehind() async throws {
        let task = fixture.makeTask(command: Self.ignoringEverythingCommand)
        let activeTask = start(task)
        try await fixture.waitUntilSignalTaskIsReady(timeout: Self.stepTimeout)
        let output = try #require(activeTask.output)
        let shell = try #require(output.runningPID())
        defer { kill(shell, SIGKILL) }

        let termination = try #require(manager.deleteTask(taskID: task.id))

        #expect(manager.activeTasks[task.id] == nil)
        await termination.value
        try await eventually(timeout: Self.stepTimeout) { activeTask.status == .notRunning }
        try await eventually(timeout: Self.stepTimeout) { TasksCoverageProcessProbe.isGone(shell) }
    }

    @Test
    func stoppingOrDeletingAnUnknownTaskDoesNothing() {
        #expect(manager.terminateTask(taskID: UUID()) == nil)
        #expect(manager.deleteTask(taskID: UUID()) == nil)
    }

    @Test
    func terminateAllTasksEndsEveryTaskThatIgnoresGentleSignals() async throws {
        let first = fixture.makeTask(name: "First", command: Self.ignoringEverythingCommand)
        let second = fixture.makeTask(name: "Second", command: Self.ignoringEverythingCommand)
        let firstActive = start(first)
        let secondActive = start(second)
        try await fixture.waitUntilSignalTaskIsReady(timeout: Self.stepTimeout)
        let firstOutput = try #require(firstActive.output)
        let secondOutput = try #require(secondActive.output)
        try await eventually(timeout: Self.stepTimeout) {
            firstOutput.runningPID() != nil && secondOutput.runningPID() != nil
        }
        let shells = try [#require(firstOutput.runningPID()), #require(secondOutput.runningPID())]
        defer { shells.forEach { kill($0, SIGKILL) } }

        await manager.terminateAllTasks().value

        try await eventually(timeout: Self.stepTimeout) { !manager.hasActiveTasks }
        try await eventually(timeout: Self.stepTimeout) { shells.allSatisfy(TasksCoverageProcessProbe.isGone) }
    }

    @Test
    func terminateAllTasksWithoutTasksFinishesImmediately() async {
        await manager.terminateAllTasks().value

        #expect(!manager.hasActiveTasks)
    }

    @Test
    func theEscalationReachesEveryStepWhenTheClockNeverWaits() async throws {
        let task = fixture.makeTask(command: Self.ignoringEverythingCommand)
        let activeTask = start(task)
        activeTask.sleep = { _ in }
        try await fixture.waitUntilSignalTaskIsReady(timeout: Self.stepTimeout)
        let output = try #require(activeTask.output)
        let shell = try #require(output.runningPID())
        defer { kill(shell, SIGKILL) }

        await activeTask.terminateAndWait()

        try await eventually(timeout: Self.stepTimeout) { activeTask.status == .notRunning }
        try await eventually(timeout: Self.stepTimeout) { TasksCoverageProcessProbe.isGone(shell) }
    }

    @Test
    func anEscalationNeverSignalsALaterRunOfTheSameTask() async throws {
        let task = fixture.makeTask(command: Self.ignoringEverythingCommand)
        let activeTask = start(task)
        activeTask.sleep = { _ in try await Task.sleep(for: .seconds(3600)) }
        try await fixture.waitUntilSignalTaskIsReady(timeout: Self.stepTimeout)
        let output = try #require(activeTask.output)
        let firstShell = try #require(output.runningPID())
        let finished = CompletionFlag()
        let escalation = Task {
            await activeTask.terminateAndWait()
            finished.set()
        }
        defer { escalation.cancel() }

        kill(firstShell, SIGKILL)
        try await eventually(timeout: Self.stepTimeout) { !activeTask.isActive }
        activeTask.run(workspaceURL: nil, shell: .zsh)
        let secondShell = try #require(output.runningPID())
        defer { kill(secondShell, SIGKILL) }

        try await eventually(timeout: Self.stepTimeout) { finished.isSet }
        try await Task.sleep(for: .milliseconds(300))
        #expect(activeTask.status == .running)
        #expect(!TasksCoverageProcessProbe.isGone(secondShell))
    }

    @Test
    func shuttingDownInterruptsCooperativeTasksAndWaitsForThemToExit() async throws {
        let task = fixture.makeSignalTask()
        let activeTask = start(task)
        try await fixture.waitUntilSignalTaskIsReady(timeout: Self.stepTimeout)
        manager.shutdownTimeout = Self.stepTimeout

        await manager.shutDownTasks()

        #expect(activeTask.status == .finished)
        #expect(fixture.markerFileContents(TasksCoverageFixture.interruptFile).contains(
            TasksCoverageFixture.interruptMarker
        ))
    }

    @Test
    func shuttingDownKillsTasksThatIgnoreTheInterruptOnceTheDeadlinePasses() async throws {
        let task = fixture.makeTask(command: Self.ignoringEverythingCommand)
        let activeTask = start(task)
        try await fixture.waitUntilSignalTaskIsReady(timeout: Self.stepTimeout)
        let output = try #require(activeTask.output)
        let shell = try #require(output.runningPID())
        defer { kill(shell, SIGKILL) }
        manager.shutdownTimeout = .milliseconds(300)

        await manager.shutDownTasks()

        try await eventually(timeout: Self.stepTimeout) { activeTask.status == .notRunning }
        try await eventually(timeout: Self.stepTimeout) { TasksCoverageProcessProbe.isGone(shell) }
    }

    @Test
    func shuttingDownWithoutLiveTasksReturnsAtOnce() async {
        let task = fixture.makeTask(command: "true")
        manager.activeTasks[task.id] = CEActiveTask(task: task, settings: fixture.settingsStore)
        manager.shutdownTimeout = Self.stepTimeout

        await manager.shutDownTasks()

        #expect(!manager.hasActiveTasks)
    }

    @Test
    func aTaskCountsAsActiveWhileItRunsOrIsSuspended() {
        let task = fixture.makeTask(command: "true")
        let activeTask = CEActiveTask(task: task, settings: fixture.settingsStore)
        manager.activeTasks[task.id] = activeTask
        #expect(!manager.hasActiveTasks)

        activeTask.updateTaskStatus(to: .running)
        #expect(manager.hasActiveTasks)

        activeTask.updateTaskStatus(to: .stopped)
        #expect(manager.hasActiveTasks)

        activeTask.updateTaskStatus(to: .finished)
        #expect(!manager.hasActiveTasks)
    }
}
