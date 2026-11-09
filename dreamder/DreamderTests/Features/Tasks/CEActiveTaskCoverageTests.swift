import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Dreamder

private struct OutcomeCase {
    let exit: ProcessExit
    let stopRequested: Bool
    let expected: CEActiveTask.Outcome
}

@MainActor
@Suite(.serialized, .uiGate)
struct CEActiveTaskCoverageTests {
    private static let readinessTimeout = Duration.seconds(40)
    private static let statusTimeout = Duration.seconds(20)
    private static let markerTimeout = Duration.seconds(20)
    private static let stepTimeout = Duration.seconds(15)

    private let fixture: TasksCoverageFixture

    init() throws {
        fixture = try TasksCoverageFixture()
    }

    @Test
    func everyTaskStatusHasItsOwnColor() {
        #expect(CETaskStatus.notRunning.color == Color.gray)
        #expect(CETaskStatus.stopped.color == Color.yellow)
        #expect(CETaskStatus.running.color == Color.orange)
        #expect(CETaskStatus.failed.color == Color.red)
        #expect(CETaskStatus.finished.color == Color.green)
    }

    @Test
    func exitMapsToTheTaskStatus() {
        let cases: [(ProcessExit, CETaskStatus)] = [
            (.exited(code: 0), .finished),
            (.exited(code: 128 + SIGINT), .notRunning),
            (.exited(code: 128 + SIGTERM), .notRunning),
            (.exited(code: 128 + SIGKILL), .notRunning),
            (.exited(code: 128 + SIGHUP), .notRunning),
            (.signaled(signal: SIGINT), .notRunning),
            (.signaled(signal: SIGTERM), .notRunning),
            (.signaled(signal: SIGKILL), .notRunning),
            (.signaled(signal: SIGHUP), .notRunning),
            (.exited(code: 1), .failed),
            (.exited(code: 2), .failed),
            (.exited(code: 7), .failed),
            (.exited(code: 15), .failed),
            (.exited(code: 128), .failed),
            (.exited(code: 128 + SIGSEGV), .failed),
            (.exited(code: 255), .failed),
            (.signaled(signal: SIGSEGV), .failed),
            (.signaled(signal: SIGSTOP), .failed)
        ]
        for (exit, expected) in cases {
            let activeTask = CEActiveTask(task: fixture.makeTask(command: "true"))
            activeTask.handleProcessFinished(exit: exit)
            #expect(activeTask.status == expected, "exit \(exit)")
        }
    }

    @Test
    func finishedTasksWriteTheirOutcomeIntoTheTaskTerminal() {
        let outcomes: [(ProcessExit, String)] = [
            (.exited(code: 0), "Finished running Coverage Task."),
            (.exited(code: 128 + SIGINT), "Coverage Task cancelled."),
            (.signaled(signal: SIGTERM), "Coverage Task cancelled."),
            (.exited(code: 3), "Failed to run Coverage Task")
        ]
        for (exit, message) in outcomes {
            let activeTask = CEActiveTask(task: fixture.makeTask(command: "true"))
            let view = CEActiveTaskTerminalView(activeTask: activeTask)
            activeTask.output = view

            activeTask.handleProcessFinished(exit: exit)

            #expect(view.getBufferAsString().contains(message), "exit \(exit)")
        }
    }

    @Test
    func finishedTasksPostActivityNotifications() async throws {
        let recorder = TasksCoverageNotificationRecorder()
        defer { recorder.stop() }
        let expectations: [(ProcessExit, String)] = [
            (.exited(code: 0), "Finished Running Coverage Task"),
            (.exited(code: 128 + SIGINT), "Coverage Task cancelled"),
            (.signaled(signal: SIGKILL), "Coverage Task cancelled"),
            (.exited(code: 3), "Failed Running Coverage Task")
        ]
        for (exit, title) in expectations {
            let activeTask = CEActiveTask(task: fixture.makeTask(command: "true"))
            activeTask.handleProcessFinished(exit: exit)

            try await eventually(timeout: Self.stepTimeout) {
                recorder.entries(for: activeTask.taskId).contains { $0.action == "deleteWithDelay" }
            }
            let entries = recorder.entries(for: activeTask.taskId)
            #expect(entries.contains { $0.action == "update" && $0.title == title })
        }
    }

    @Test
    func hangUpWithoutAProcessChangesNothing() {
        let activeTask = CEActiveTask(task: fixture.makeTask(command: "true"))

        activeTask.hangUp()

        #expect(activeTask.status == .notRunning)
    }

    @Test
    func signalsAndWaitingWithoutAProcessChangeNothing() async {
        let activeTask = CEActiveTask(task: fixture.makeTask(command: "true"))

        activeTask.suspend()
        activeTask.resume()
        activeTask.terminate()
        activeTask.interrupt()
        await activeTask.waitForExit()

        #expect(activeTask.status == .notRunning)
        #expect(activeTask.output == nil)
    }

    @Test
    func equalTasksWithTheSameStateAreEqualAndHashAlike() {
        let task = fixture.makeTask(command: "true")
        let first = CEActiveTask(task: task)
        let second = CEActiveTask(task: task)

        #expect(first == second)
        #expect(first.hashValue == second.hashValue)
        #expect(Set([first, second]).count == 1)

        second.updateTaskStatus(to: .failed)
        #expect(first != second)
        #expect(Set([first, second]).count == 2)

        let other = CEActiveTask(task: fixture.makeTask(name: "Other", command: "false"))
        #expect(first != other)
    }

    @Test
    func tasksWithDifferentTerminalsAreNotEqual() {
        let task = fixture.makeTask(command: "true")
        let first = CEActiveTask(task: task)
        let second = CEActiveTask(task: task)
        first.output = CEActiveTaskTerminalView(activeTask: first)

        #expect(first != second)
    }

    @Test
    func taskIdentifierCombinesTheTaskAndRunIdentifiers() {
        let activeTask = CEActiveTask(task: fixture.makeTask(command: "true"))
        #expect(activeTask.taskId == activeTask.task.id.uuidString + "-" + activeTask.activeTaskID.uuidString)
    }

    @Test(arguments: [Shell.zsh, Shell.bash])
    func terminateAsksARunningTaskToExit(_ shell: Shell) async throws {
        let activeTask = CEActiveTask(task: fixture.makeSignalTask())
        activeTask.run(workspaceURL: nil, shell: shell)
        try await fixture.waitUntilSignalTaskIsReady(timeout: Self.readinessTimeout)

        activeTask.terminate()

        try await eventually(timeout: Self.statusTimeout) { activeTask.status == .finished }
        try await fixture.waitForMarker(
            TasksCoverageFixture.terminateMarker,
            in: TasksCoverageFixture.terminateFile,
            timeout: Self.markerTimeout
        )
    }

    @Test(arguments: [Shell.zsh, Shell.bash])
    func interruptSendsSigintToARunningTask(_ shell: Shell) async throws {
        let activeTask = CEActiveTask(task: fixture.makeSignalTask())
        activeTask.run(workspaceURL: nil, shell: shell)
        try await fixture.waitUntilSignalTaskIsReady(timeout: Self.readinessTimeout)

        activeTask.interrupt()

        try await eventually(timeout: Self.statusTimeout) { activeTask.status == .finished }
        try await fixture.waitForMarker(
            TasksCoverageFixture.interruptMarker,
            in: TasksCoverageFixture.interruptFile,
            timeout: Self.markerTimeout
        )
    }

    @Test(arguments: [Shell.zsh, Shell.bash])
    func suspendStopsTheShellAndResumeContinuesIt(_ shell: Shell) async throws {
        let activeTask = CEActiveTask(task: fixture.makeSignalTask())
        activeTask.run(workspaceURL: nil, shell: shell)
        let output = try #require(activeTask.output)
        try await fixture.waitUntilSignalTaskIsReady(timeout: Self.readinessTimeout)
        let pid = try #require(output.runningPID())

        activeTask.resume()
        #expect(activeTask.status == .running)

        activeTask.suspend()
        #expect(activeTask.status == .stopped)
        try await eventually(timeout: Self.stepTimeout) { TasksCoverageProcessProbe.isStopped(pid) }

        activeTask.suspend()
        #expect(activeTask.status == .stopped)

        activeTask.resume()
        #expect(activeTask.status == .running)
        try await eventually(timeout: Self.stepTimeout) { !TasksCoverageProcessProbe.isStopped(pid) }

        activeTask.terminate()
        try await eventually(timeout: Self.stepTimeout) { activeTask.status == .finished }
    }

    @Test
    func rerunningATaskKeepsItsTerminalAndGeneratesANewRunIdentifier() async throws {
        let activeTask = CEActiveTask(task: fixture.makeTask(command: "echo again-$((1+1))"))
        activeTask.run(workspaceURL: nil, shell: .zsh)
        let output = try #require(activeTask.output)
        let firstRunID = activeTask.activeTaskID
        try await eventually { activeTask.status == .finished }

        activeTask.run(workspaceURL: nil, shell: .zsh)

        #expect(activeTask.output === output)
        #expect(activeTask.activeTaskID != firstRunID)
        #expect(activeTask.status == .running)
        try await eventually {
            activeTask.status == .finished
                && output.getBufferAsString().components(separatedBy: "again-2").count - 1 >= 2
        }
    }

    @Test(arguments: [
        ("exit 0", CETaskStatus.finished),
        ("exit 130", CETaskStatus.notRunning),
        ("exit 143", CETaskStatus.notRunning),
        ("exit 3", CETaskStatus.failed),
        ("exit 2", CETaskStatus.failed)
    ])
    func aShellsExitCodeDecidesTheOutcomeOfTheRun(_ command: String, _ expected: CETaskStatus) async throws {
        let activeTask = CEActiveTask(task: fixture.makeTask(command: command), settings: fixture.settingsStore)
        activeTask.run(workspaceURL: nil, shell: .zsh)

        try await eventually(timeout: Self.statusTimeout) { !activeTask.isActive }

        #expect(activeTask.status == expected, "\(command)")
    }

    @Test
    func aShellKilledBySigkillAfterStartingCountsAsCancelled() async throws {
        let activeTask = CEActiveTask(task: fixture.makeSignalTask(), settings: fixture.settingsStore)
        activeTask.run(workspaceURL: nil, shell: .zsh)
        try await fixture.waitUntilSignalTaskIsReady(timeout: Self.readinessTimeout)
        let output = try #require(activeTask.output)
        let shell = try #require(output.runningPID())

        ProcessTree.send(SIGKILL, to: shell)

        try await eventually(timeout: Self.statusTimeout) { activeTask.status == .notRunning }
    }

    @Test
    func aRequestedStopTurnsNonZeroExitsIntoCancellations() {
        let cases = [
            OutcomeCase(exit: .exited(code: 1), stopRequested: true, expected: .cancelled),
            OutcomeCase(exit: .exited(code: 1), stopRequested: false, expected: .failed),
            OutcomeCase(exit: .exited(code: 0), stopRequested: true, expected: .finished),
            OutcomeCase(exit: .exited(code: 0), stopRequested: false, expected: .finished),
            OutcomeCase(exit: .exited(code: 130), stopRequested: false, expected: .cancelled),
            OutcomeCase(exit: .signaled(signal: SIGHUP), stopRequested: false, expected: .cancelled),
            OutcomeCase(exit: .signaled(signal: SIGSEGV), stopRequested: true, expected: .failed),
            OutcomeCase(exit: .signaled(signal: SIGSEGV), stopRequested: false, expected: .failed)
        ]
        for outcome in cases {
            #expect(
                CEActiveTask.Outcome(exit: outcome.exit, stopRequested: outcome.stopRequested) == outcome.expected,
                "exit \(outcome.exit) stopRequested \(outcome.stopRequested)"
            )
        }
    }

    @Test(arguments: [Shell.zsh, Shell.bash])
    func aStopEndsAsCancelledEvenWhenTheShellExitsWithAnErrorCode(_ shell: Shell) async throws {
        let command = """
        trap 'exit 5' HUP; m=ready-$((40+2)); echo $m >> "$\(TasksCoverageFixture.markersDirectoryVariable)/\
        \(TasksCoverageFixture.readyFile)"; echo $m; \
        i=0; while [ $i -lt 600 ]; do sleep 0.1; i=$((i+1)); done
        """
        let activeTask = CEActiveTask(task: fixture.makeTask(command: command), settings: fixture.settingsStore)
        activeTask.run(workspaceURL: nil, shell: shell)
        try await fixture.waitUntilSignalTaskIsReady(timeout: Self.readinessTimeout)

        await activeTask.terminateAndWait()

        try await eventually(timeout: Self.statusTimeout) { activeTask.status == .notRunning }
    }
}
