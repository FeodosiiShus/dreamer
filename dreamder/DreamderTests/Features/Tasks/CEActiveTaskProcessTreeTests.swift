import Foundation
import Synchronization
import Testing
@testable import Dreamder

private final class SleepGate: Sendable {
    private let calls = Mutex(0)

    func shouldReturnImmediately() -> Bool {
        calls.withLock { count in
            count += 1
            return count <= 2
        }
    }
}

@MainActor
@Suite(.serialized, .uiGate)
struct CEActiveTaskProcessTreeTests {
    private static let ignoringHangUpAndTermCommand = """
    trap '' HUP TERM; echo ready-$((40+2)); i=0; while [ $i -lt 600 ]; do sleep 0.1; i=$((i+1)); done
    """

    private let fixture: TasksCoverageFixture

    init() throws {
        fixture = try TasksCoverageFixture()
    }

    @Test(arguments: [Shell.zsh, Shell.bash])
    func terminateStopsTheCommandsTheTaskStarted(_ shell: Shell) async throws {
        let activeTask = CEActiveTask(task: fixture.makeTask(command: TasksCoverageProcessProbe.backgroundChildCommand))
        activeTask.run(workspaceURL: nil, shell: shell)
        let output = try #require(activeTask.output)
        try await eventually { TasksCoverageProcessProbe.announcedPID(in: output.getBufferAsString()) != nil }
        let child = try #require(TasksCoverageProcessProbe.announcedPID(in: output.getBufferAsString()))
        defer { kill(child, SIGKILL) }
        #expect(!TasksCoverageProcessProbe.isGone(child))

        activeTask.terminate()

        try await eventually { TasksCoverageProcessProbe.isGone(child) }
        try await eventually { !activeTask.isActive }
    }

    @Test(arguments: [Shell.zsh, Shell.bash])
    func interruptStopsTheCommandsTheTaskStarted(_ shell: Shell) async throws {
        let activeTask = CEActiveTask(task: fixture.makeTask(command: TasksCoverageProcessProbe.backgroundChildCommand))
        activeTask.run(workspaceURL: nil, shell: shell)
        let output = try #require(activeTask.output)
        try await eventually { TasksCoverageProcessProbe.announcedPID(in: output.getBufferAsString()) != nil }
        let child = try #require(TasksCoverageProcessProbe.announcedPID(in: output.getBufferAsString()))
        defer { kill(child, SIGKILL) }

        activeTask.interrupt()

        try await eventually { TasksCoverageProcessProbe.isGone(child) }
        try await eventually { !activeTask.isActive }
    }

    @Test
    func suspendAndResumeReachEveryProcessOfTheTask() async throws {
        let activeTask = CEActiveTask(task: fixture.makeTask(command: TasksCoverageProcessProbe.backgroundChildCommand))
        activeTask.run(workspaceURL: nil, shell: .zsh)
        let output = try #require(activeTask.output)
        try await eventually { TasksCoverageProcessProbe.announcedPID(in: output.getBufferAsString()) != nil }
        let child = try #require(TasksCoverageProcessProbe.announcedPID(in: output.getBufferAsString()))
        defer {
            kill(child, SIGKILL)
            activeTask.forceTerminate()
        }

        activeTask.suspend()
        try await eventually { TasksCoverageProcessProbe.isStopped(child) }
        activeTask.resume()
        try await eventually { !TasksCoverageProcessProbe.isStopped(child) }

        activeTask.suspend()
        try await eventually { TasksCoverageProcessProbe.isStopped(child) }
        activeTask.terminate()
        #expect(activeTask.status == .running)
        try await eventually { TasksCoverageProcessProbe.isGone(child) }
        try await eventually { !activeTask.isActive }
    }

    @Test
    func terminateAndWaitReturnsAsSoonAsTheTaskHasStopped() async throws {
        let activeTask = CEActiveTask(task: fixture.makeSignalTask())
        activeTask.sleep = { _ in try await Task.sleep(for: .seconds(3600)) }
        activeTask.run(workspaceURL: nil, shell: .zsh)
        let output = try #require(activeTask.output)
        try await fixture.waitUntilReady(output)

        await activeTask.terminateAndWait()

        #expect(!activeTask.isActive)
        #expect(activeTask.status == .notRunning)
        try await fixture.waitForOutput(output, containing: "Signal Task cancelled.")
    }

    @Test
    func terminateAndWaitReturnsImmediatelyForAnIdleTask() async {
        let activeTask = CEActiveTask(task: fixture.makeTask(command: "true"))
        activeTask.sleep = { _ in Issue.record("an idle task must not wait") }

        await activeTask.terminateAndWait()

        #expect(activeTask.status == .notRunning)
    }

    @Test
    func terminateAndWaitEscalatesToSigkillWhenSigtermIsIgnored() async throws {
        let activeTask = CEActiveTask(task: fixture.makeTask(command: Self.ignoringHangUpAndTermCommand))
        let gate = SleepGate()
        activeTask.sleep = { _ in
            if gate.shouldReturnImmediately() { return }
            try await Task.sleep(for: .seconds(3600))
        }
        activeTask.run(workspaceURL: nil, shell: .zsh)
        let output = try #require(activeTask.output)
        try await fixture.waitUntilReady(output)

        await activeTask.terminateAndWait()

        #expect(!activeTask.isActive)
        #expect(activeTask.status == .notRunning)
        try await fixture.waitForOutput(output, containing: "Coverage Task cancelled.")
    }

    @Test
    func terminateAndWaitUsesTheRealClockToEscalateWhenSigtermIsIgnored() async throws {
        let activeTask = CEActiveTask(task: fixture.makeTask(command: Self.ignoringHangUpAndTermCommand))
        activeTask.terminationGrace = .milliseconds(100)
        activeTask.run(workspaceURL: nil, shell: .zsh)
        let output = try #require(activeTask.output)
        try await fixture.waitUntilReady(output)

        await activeTask.terminateAndWait()

        try await eventually { !activeTask.isActive }
        try await fixture.waitForOutput(output, containing: "Coverage Task cancelled.")
    }

    @Test
    func aStoppedTaskCanBeTerminatedAndWaitedFor() async throws {
        let activeTask = CEActiveTask(task: fixture.makeSignalTask())
        activeTask.sleep = { _ in try await Task.sleep(for: .seconds(3600)) }
        activeTask.run(workspaceURL: nil, shell: .zsh)
        let output = try #require(activeTask.output)
        try await fixture.waitUntilReady(output)
        activeTask.suspend()
        #expect(activeTask.status == .stopped)

        await activeTask.terminateAndWait()

        #expect(!activeTask.isActive)
    }

    @Test
    func quotedScriptNamesReachTheShellAsOneLiteralArgument() async throws {
        try await withTempDir { directory in
            let hostile = "a;echo injected|b'c"
            let outputFile = directory.appending(path: "argument.txt")
            let command = "printf '%s' " + NpmTaskDiscovery.shellWord(hostile)
                + " > " + NpmTaskDiscovery.shellWord(outputFile.path(percentEncoded: false))
            let activeTask = CEActiveTask(task: fixture.makeTask(command: command))

            activeTask.run(workspaceURL: nil, shell: .zsh)

            try await eventually { activeTask.status == .finished }
            let written = try String(contentsOf: outputFile, encoding: .utf8)
            #expect(written == hostile)
        }
    }

    @Test
    func forceTerminateWithoutAProcessChangesNothing() {
        let activeTask = CEActiveTask(task: fixture.makeTask(command: "true"))

        activeTask.forceTerminate()

        #expect(activeTask.status == .notRunning)
    }
}
