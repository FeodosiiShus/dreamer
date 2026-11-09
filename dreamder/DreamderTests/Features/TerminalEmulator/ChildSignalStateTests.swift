import AppKit
import Darwin
import Foundation
import Testing
@testable import Dreamder

private func currentThreadBlocks(_ signal: Int32) -> Bool {
    var current = sigset_t()
    pthread_sigmask(SIG_BLOCK, nil, &current)
    return sigismember(&current, signal) == 1
}

@MainActor
private func withCurrentThreadBlocking<Value>(_ signal: Int32, _ body: () -> Value) -> Value {
    var blocked = sigset_t()
    var previous = sigset_t()
    sigemptyset(&blocked)
    sigaddset(&blocked, signal)
    pthread_sigmask(SIG_BLOCK, &blocked, &previous)
    defer { pthread_sigmask(SIG_SETMASK, &previous, nil) }
    return body()
}

@MainActor
@Suite(.serialized, .uiGate)
struct ChildSignalStateTests {
    private let fixture: TasksCoverageFixture

    init() throws {
        fixture = try TasksCoverageFixture()
    }

    @Test
    func theEmptyMaskScopeClearsTheBlockedSignalsAndRestoresThem() {
        withCurrentThreadBlocking(SIGINT) {
            #expect(currentThreadBlocks(SIGINT))

            let blockedInside = SignalMask.withEmptyMask { currentThreadBlocks(SIGINT) }

            #expect(!blockedInside)
            #expect(currentThreadBlocks(SIGINT))
        }
        #expect(!currentThreadBlocks(SIGINT))
    }

    @Test
    func theEmptyMaskScopeReturnsTheValueOfItsBody() {
        #expect(SignalMask.withEmptyMask { 42 } == 42)
    }

    @Test
    func aShellIsSpawnedWithAnEmptyMaskEvenWhenTheCallerBlocksSigint() async throws {
        await withTerminalCoverageSettings(shellIntegration: false) {
            let view = terminalCoverageView()
            var blockedAtSpawn: [Bool] = []
            view.spawnProcess = { _, _ in blockedAtSpawn.append(currentThreadBlocks(SIGINT)) }

            withCurrentThreadBlocking(SIGINT) {
                view.startProcess(workspaceURL: nil, shell: .zsh)
                #expect(currentThreadBlocks(SIGINT))
            }

            #expect(blockedAtSpawn == [false])
        }
    }

    @Test
    func aTaskStartedWhileTheHostBlocksSigintStillRunsItsInterruptTrap() async throws {
        try await withTerminalCoverageSettings(shellIntegration: false) {
            let activeTask = CEActiveTask(task: fixture.makeSignalTask())
            defer { activeTask.forceTerminate() }

            withCurrentThreadBlocking(SIGINT) {
                activeTask.run(workspaceURL: nil, shell: .zsh)
            }

            try await eventually(timeout: .seconds(20)) {
                fixture.markerFileContents(TasksCoverageFixture.readyFile).contains(TasksCoverageFixture.readyMarker)
            }
            activeTask.interrupt()
            try await eventually(timeout: .seconds(20)) {
                fixture.markerFileContents(TasksCoverageFixture.interruptFile)
                    .contains(TasksCoverageFixture.interruptMarker)
            }
        }
    }

    @Test(arguments: [SIGINT, SIGQUIT, SIGTERM, SIGHUP, SIGPIPE, SIGTSTP])
    func theAppLeavesTheDispositionOfTheShellSignalsAtDefault(_ signal: Int32) {
        var action = sigaction()

        let status = sigaction(signal, nil, &action)

        #expect(status == 0)
        #expect(action.__sigaction_u.__sa_handler == nil)
    }
}
