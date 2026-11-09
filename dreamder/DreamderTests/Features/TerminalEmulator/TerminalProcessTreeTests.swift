import Foundation
import Testing
@testable import Dreamder

@MainActor
private func startZsh(_ script: String, in view: CELocalShellTerminalView) {
    view.process.startProcess(
        executable: "/bin/zsh",
        args: ["-f", "-i", "-c", script],
        environment: nil,
        execName: "zsh",
        currentDirectory: nil
    )
}

@MainActor
private func announcedChild(in view: CELocalShellTerminalView) async throws -> pid_t {
    try await eventually { TasksCoverageProcessProbe.announcedPID(in: terminalCoverageText(view)) != nil }
    return try #require(TasksCoverageProcessProbe.announcedPID(in: terminalCoverageText(view)))
}

@MainActor
@Suite(.serialized, .uiGate)
struct TerminalProcessTreeTests {
    @Test
    func descendantsAreFoundAndSignalledTogetherEvenWhenTheyRunInTheirOwnJobs() async throws {
        let view = terminalCoverageView()
        startZsh("sleep 600 & sleep 600 & sleep 600 & echo child-pid-$!-end; wait", in: view)
        let shell = view.process.shellPid
        let announced = try await announcedChild(in: view)
        let tree = [shell] + ProcessTree.descendants(of: shell)
        defer {
            for pid in tree {
                kill(pid, SIGKILL)
            }
        }
        #expect(tree.count >= 4)
        #expect(tree.contains(announced))
        #expect(ProcessTree.children(of: shell).contains(announced))

        ProcessTree.send(SIGSTOP, to: shell)
        try await eventually { tree.allSatisfy { TasksCoverageProcessProbe.isStopped($0) } }

        ProcessTree.send(SIGCONT, to: shell)
        try await eventually { tree.allSatisfy { !TasksCoverageProcessProbe.isStopped($0) } }

        ProcessTree.send(SIGKILL, to: shell)
        try await eventually { tree.allSatisfy { TasksCoverageProcessProbe.isGone($0) } }
        try await eventually { !view.process.running }
    }

    @Test
    func invalidProcessIdentifiersHaveNoTreeAndAreNeverSignalled() {
        ProcessTree.send(SIGTERM, to: 0)
        ProcessTree.send(SIGTERM, to: -5)

        #expect(ProcessTree.children(of: 0).isEmpty)
        #expect(ProcessTree.children(of: -1).isEmpty)
        #expect(ProcessTree.children(of: Int32.max).isEmpty)
        #expect(ProcessTree.descendants(of: Int32.max).isEmpty)
    }

    @Test
    func closingATerminalHangsUpEverythingItStarted() async throws {
        let view = terminalCoverageView()
        view.terminationEscalationDelay = .milliseconds(20)
        startZsh("sleep 600 & echo child-pid-$!-end; wait", in: view)
        let child = try await announcedChild(in: view)
        defer { kill(child, SIGKILL) }

        let escalation = try #require(view.terminateSession())

        try await eventually { TasksCoverageProcessProbe.isGone(child) }
        try await eventually { !view.process.running }
        await escalation.value
    }

    @Test
    func closingATerminalKillsProcessesThatIgnoreTheHangup() async throws {
        let view = terminalCoverageView()
        view.terminationEscalationDelay = .milliseconds(50)
        startZsh("trap '' HUP; sleep 600 & echo child-pid-$!-end; wait", in: view)
        let shell = view.process.shellPid
        let child = try await announcedChild(in: view)
        defer {
            kill(child, SIGKILL)
            kill(shell, SIGKILL)
        }

        let escalation = try #require(view.terminateSession())
        await escalation.value

        try await eventually { TasksCoverageProcessProbe.isGone(child) }
        try await eventually { !view.process.running }
    }

    @Test
    func aShellThatKeepsRunningAfterTheHangupIsKilledOnceTheEscalationDelayPassed() async throws {
        let view = terminalCoverageView()
        view.terminationEscalationDelay = .milliseconds(100)
        view.process.startProcess(
            executable: "/bin/sh",
            args: ["-c", "trap '' HUP; echo ready-42; while :; do sleep 1; done"],
            environment: nil,
            execName: "sh",
            currentDirectory: nil
        )
        let shell = view.process.shellPid
        defer { ProcessTree.send(SIGKILL, to: shell) }
        try await eventually { terminalCoverageText(view).contains("ready-42") }

        let escalation = try #require(view.terminateSession())
        #expect(view.process.running)
        await escalation.value

        try await eventually { !view.process.running }
    }

    @Test
    func aTerminalWithoutARunningShellHasNothingToTerminate() {
        let view = terminalCoverageView()

        #expect(view.terminateSession() == nil)
    }
}
