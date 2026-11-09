import AppKit
import Foundation
import Testing
@testable import Dreamder

@MainActor
private func withSystemShellSettings(perform body: () async throws -> Void) async throws {
    try await withTerminalCoverageSettings({ $0.shell = .system; $0.useShellIntegration = false }, perform: body)
}

@MainActor
private final class ExitRecordingActiveTask: CEActiveTask {
    private(set) var exits: [ProcessExit] = []

    override func handleProcessFinished(exit: ProcessExit) {
        exits.append(exit)
    }
}

@MainActor
@Suite(.serialized, .uiGate)
struct ActiveTaskTerminalLaunchTests {
    private let fixture: TasksCoverageFixture

    init() throws {
        fixture = try TasksCoverageFixture()
    }

    private func makeTaskView(
        command: String,
        workingDirectory: String = ""
    ) -> (task: ExitRecordingActiveTask, view: CEActiveTaskTerminalView) {
        let task = fixture.makeTask(command: command)
        task.workingDirectory = workingDirectory
        let activeTask = ExitRecordingActiveTask(task: task)
        let view = CEActiveTaskTerminalView(activeTask: activeTask)
        activeTask.output = view
        return (activeTask, view)
    }

    private static let markerCommand = "echo ran > \"$TASKS_COVERAGE_MARKERS/ran\""

    @Test
    func aMissingWorkingDirectoryStopsTheTaskBeforeAnythingIsSpawned() async throws {
        try await withTempDir { directory in
            await withTerminalCoverageSettings(shellIntegration: false) {
                let (_, view) = makeTaskView(command: Self.markerCommand, workingDirectory: "gone")
                let spawns = SpawnRecorder()
                view.spawnProcess = { _, request in spawns.record(request) }

                let started = view.startProcess(workspaceURL: directory, shell: .zsh)

                #expect(!started)
                #expect(spawns.requests.isEmpty)
                #expect(view.runningPID() == nil)
                let text = view.getBufferAsString()
                #expect(text.contains("Working directory does not exist:"))
                #expect(!text.contains("Starting task"))
                #expect(fixture.markerFileContents("ran").isEmpty)
            }
        }
    }

    @Test
    func aWorkingDirectoryThatIsAFileStopsTheTask() async throws {
        try await withTempDir { directory in
            try await withTerminalCoverageSettings(shellIntegration: false) {
                try "content".write(to: directory.appending(path: "file.txt"), atomically: true, encoding: .utf8)
                let (_, view) = makeTaskView(command: "true", workingDirectory: "file.txt")
                let spawns = SpawnRecorder()
                view.spawnProcess = { _, request in spawns.record(request) }

                let started = view.startProcess(workspaceURL: directory, shell: .zsh)

                #expect(!started)
                #expect(spawns.requests.isEmpty)
                #expect(view.getBufferAsString().contains("Working directory does not exist:"))
            }
        }
    }

    @Test
    func anExistingWorkingDirectoryIsPassedToTheSpawnAbsolute() async throws {
        try await withTempDir { directory in
            try await withTerminalCoverageSettings(shellIntegration: false) {
                let folder = directory.appending(path: "nested", directoryHint: .isDirectory)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let (_, view) = makeTaskView(command: "true", workingDirectory: "nested")
                let spawns = SpawnRecorder()
                view.spawnProcess = { _, request in spawns.record(request) }

                view.startProcess(workspaceURL: directory, shell: .zsh)

                let request = try #require(spawns.requests.first)
                let passed = try #require(request.currentDirectory)
                #expect(passed.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ==
                    folder.absolutePath.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
                #expect(request.executable == "/bin/zsh")
                #expect(request.executableName == "zsh")
                #expect(request.arguments.last == "true")
            }
        }
    }

    @Test
    func anUnsupportedLoginShellFallsBackToZshAndTheTaskStillRuns() async throws {
        try await withSystemShellSettings {
            let (task, view) = makeTaskView(command: "echo fallback-$((1+1))")
            view.systemShell = { "/opt/homebrew/bin/fish" }

            let started = view.startProcess(workspaceURL: nil)

            #expect(started)
            try await eventually(timeout: .seconds(20)) { view.getBufferAsString().contains("fallback-2") }
            try await eventually(timeout: .seconds(20)) { !task.exits.isEmpty }
            #expect(task.exits == [.exited(code: 0)])
            #expect(view.getBufferAsString().contains("Shell /opt/homebrew/bin/fish cannot be used, using /bin/zsh."))
        }
    }

    @Test
    func aLoginShellThatNoLongerExistsFallsBackToZshInsteadOfForkingTheApp() async throws {
        try await withSystemShellSettings {
            let (task, view) = makeTaskView(command: "echo gone-shell-$((1+1))")
            view.systemShell = { "/nonexistent/bin/zsh" }
            let spawns = SpawnRecorder()
            view.spawnProcess = { _, request in spawns.record(request) }

            view.startProcess(workspaceURL: nil)

            #expect(task.exits.isEmpty)
            let request = try #require(spawns.requests.first)
            #expect(request.executable == "/bin/zsh")
            #expect(view.getBufferAsString().contains("Shell /nonexistent/bin/zsh cannot be used, using /bin/zsh."))
        }
    }

    @Test
    func aTaskWithoutAnyExecutableShellDoesNotStartAndSaysWhy() async throws {
        try await withSystemShellSettings {
            let (_, view) = makeTaskView(command: "true")
            view.systemShell = { "/opt/homebrew/bin/fish" }
            view.isExecutable = { _ in false }
            let spawns = SpawnRecorder()
            view.spawnProcess = { _, request in spawns.record(request) }

            let started = view.startProcess(workspaceURL: nil)

            #expect(!started)
            #expect(spawns.requests.isEmpty)
            #expect(view.runningPID() == nil)
            #expect(view.getBufferAsString().contains("Cannot start a shell"))
            #expect(!view.getBufferAsString().contains("Starting task"))
        }
    }

    @Test
    func aSpawnThatProducesNoProcessIsReportedAsAFailedStart() async throws {
        await withTerminalCoverageSettings(shellIntegration: false) {
            let (_, view) = makeTaskView(command: "true")
            view.spawnProcess = { _, _ in }

            let started = view.startProcess(workspaceURL: nil, shell: .zsh)

            #expect(!started)
            #expect(view.runningPID() == nil)
            #expect(view.getBufferAsString().contains("Failed to start /bin/zsh."))
        }
    }

    @Test
    func aRunThatCannotStartEndsUpFailedInsteadOfRunning() async throws {
        try await withSystemShellSettings {
            let activeTask = CEActiveTask(task: fixture.makeTask(command: "true"))
            let view = CEActiveTaskTerminalView(activeTask: activeTask)
            view.systemShell = { "/opt/homebrew/bin/fish" }
            view.isExecutable = { _ in false }
            activeTask.output = view

            activeTask.run(workspaceURL: nil)

            #expect(activeTask.status == .failed)
            #expect(view.getBufferAsString().contains("Cannot start a shell"))
        }
    }

    @Test(arguments: [Int32(3), 130])
    func aShellExitIsDeliveredAsTheDecodedExitCode(_ code: Int32) async throws {
        try await withTerminalCoverageSettings(shellIntegration: false) {
            let (task, view) = makeTaskView(command: "exit \(code)")

            view.startProcess(workspaceURL: nil, shell: .zsh)

            try await eventually(timeout: .seconds(20)) { !task.exits.isEmpty }
            #expect(task.exits == [.exited(code: code)])
        }
    }

    @Test
    func aShellKilledBySignalIsDeliveredAsTheSignal() async throws {
        try await withTerminalCoverageSettings(shellIntegration: false) {
            let (task, view) = makeTaskView(command: "kill -9 $$")

            view.startProcess(workspaceURL: nil, shell: .zsh)

            try await eventually(timeout: .seconds(20)) { !task.exits.isEmpty }
            #expect(task.exits == [.signaled(signal: 9)])
        }
    }

    @Test
    func aMissingExitIsDeliveredAsAFailure() async throws {
        let (task, view) = makeTaskView(command: "true")

        view.processTerminated(view.process, exitCode: nil)

        try await eventually(timeout: .seconds(20)) { !task.exits.isEmpty }
        #expect(task.exits == [.exited(code: 1)])
    }
}
