import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Dreamder

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
    func terminationStatusMapsToTheTaskStatus() {
        let cases: [(Int32, CETaskStatus)] = [
            (0, .finished),
            (2, .notRunning),
            (9, .notRunning),
            (15, .notRunning),
            (130, .notRunning),
            (143, .notRunning),
            (17, .stopped),
            (145, .stopped),
            (1, .failed),
            (7, .failed),
            (768, .failed)
        ]
        for (terminationStatus, expected) in cases {
            let activeTask = CEActiveTask(task: fixture.makeTask(command: "true"))
            activeTask.handleProcessFinished(terminationStatus: terminationStatus)
            #expect(activeTask.status == expected, "termination status \(terminationStatus)")
        }
    }

    @Test
    func finishedTasksWriteTheirOutcomeIntoTheTaskTerminal() {
        let outcomes: [(Int32, String?)] = [
            (0, "Finished running Coverage Task."),
            (2, "Coverage Task cancelled."),
            (15, "Coverage Task cancelled."),
            (3, "Failed to run Coverage Task"),
            (17, nil)
        ]
        for (terminationStatus, message) in outcomes {
            let activeTask = CEActiveTask(task: fixture.makeTask(command: "true"))
            let view = CEActiveTaskTerminalView(activeTask: activeTask)
            activeTask.output = view

            activeTask.handleProcessFinished(terminationStatus: terminationStatus)

            if let message {
                #expect(view.getBufferAsString().contains(message), "termination status \(terminationStatus)")
            } else {
                #expect(view.getBufferAsString().isEmpty)
            }
        }
    }

    @Test
    func finishedTasksPostActivityNotifications() async throws {
        let recorder = TasksCoverageNotificationRecorder()
        defer { recorder.stop() }
        let expectations: [(Int32, String)] = [
            (0, "Finished Running Coverage Task"),
            (2, "Coverage Task cancelled"),
            (9, "Coverage Task cancelled"),
            (3, "Failed Running Coverage Task")
        ]
        for (terminationStatus, title) in expectations {
            let activeTask = CEActiveTask(task: fixture.makeTask(command: "true"))
            activeTask.handleProcessFinished(terminationStatus: terminationStatus)

            try await eventually {
                recorder.entries(for: activeTask.taskId).contains { $0.action == "deleteWithDelay" }
            }
            let entries = recorder.entries(for: activeTask.taskId)
            #expect(entries.contains { $0.action == "update" && $0.title == title })
        }
    }

    @Test
    func stoppedTasksDoNotPostAnOutcomeUpdate() async throws {
        let recorder = TasksCoverageNotificationRecorder()
        defer { recorder.stop() }
        let activeTask = CEActiveTask(task: fixture.makeTask(command: "true"))

        activeTask.handleProcessFinished(terminationStatus: 17)

        try await eventually {
            recorder.entries(for: activeTask.taskId).contains { $0.action == "deleteWithDelay" }
        }
        #expect(!recorder.entries(for: activeTask.taskId).contains { $0.action == "update" })
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
}
