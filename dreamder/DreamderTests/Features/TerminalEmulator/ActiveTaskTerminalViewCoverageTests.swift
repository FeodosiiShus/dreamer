import AppKit
import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct ActiveTaskTerminalViewCoverageTests {
    private let fixture: TasksCoverageFixture

    init() throws {
        fixture = try TasksCoverageFixture()
    }

    @Test
    func detachedTerminalsHaveAFixedFrame() {
        let view = CEActiveTaskTerminalView(activeTask: CEActiveTask(task: fixture.makeTask(command: "true")))

        #expect(CEActiveTaskTerminalView.detachedFrame == NSRect(x: 0, y: 0, width: 960, height: 480))
        #expect(view.frame.size == CEActiveTaskTerminalView.detachedFrame.size)
    }

    @Test
    func aTerminalWithoutAProcessHasNoPid() {
        let view = CEActiveTaskTerminalView(activeTask: CEActiveTask(task: fixture.makeTask(command: "true")))

        #expect(view.runningPID() == nil)
    }

    @Test
    func outputMessagesAreWrittenOnTheirOwnLines() {
        let view = CEActiveTaskTerminalView(activeTask: CEActiveTask(task: fixture.makeTask(command: "true")))

        view.sendOutputMessage("first message")
        view.sendOutputMessage("second message")

        let lines = view.getBufferAsString().split(separator: "\n").map(String.init)
        let firstLine = lines.firstIndex { $0.contains("first message") }
        let secondLine = lines.firstIndex { $0.contains("second message") }
        #expect(firstLine != nil)
        #expect(secondLine != nil)
        #expect(firstLine != secondLine)
    }

    @Test
    func tasksFallBackToAPlainShellWhenTheIntegrationScriptsAreMissing() async throws {
        try await withTempDir { directory in
            try await withTerminalCoverageSettings({ $0.useShellIntegration = true }) {
                let task = fixture.makeTask(command: "echo fallback-$((1+1))")
                let activeTask = CEActiveTask(task: task)
                let view = CEActiveTaskTerminalView(activeTask: activeTask)
                view.shellIntegrationBundle = try makeEmptyShellIntegrationBundle(in: directory)
                activeTask.output = view

                activeTask.run(workspaceURL: nil, shell: .zsh)

                try await eventually { activeTask.status == .finished }
                try await eventually { view.getBufferAsString().contains("fallback-2") }
                #expect(view.getBufferAsString().contains("Starting task: Coverage Task"))
            }
        }
    }

    @Test
    func tasksStartInTheirWorkingDirectoryRelativeToTheWorkspace() async throws {
        try await withTempDir { directory in
            let folder = directory.appending(path: "nested-dir", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try await withTerminalCoverageSettings({ $0.useShellIntegration = false }) {
                let task = fixture.makeTask(command: "echo here-${PWD##*/}-$((1+1))")
                task.workingDirectory = "nested-dir"
                let activeTask = CEActiveTask(task: task)

                activeTask.run(workspaceURL: directory, shell: .zsh)

                try await eventually { activeTask.status == .finished }
                let output = try #require(activeTask.output)
                #expect(output.getBufferAsString().contains("here-nested-dir-2"))
            }
        }
    }

    @Test
    func aFailingTaskMarksItselfAsFailedAndSaysSo() async throws {
        try await withTerminalCoverageSettings(shellIntegration: false) {
            let task = fixture.makeTask(command: "exit 3")
            let activeTask = CEActiveTask(task: task)

            activeTask.run(workspaceURL: nil, shell: .zsh)

            try await eventually { activeTask.status == .failed }
            let output = try #require(activeTask.output)
            #expect(output.getBufferAsString().contains("Failed to run Coverage Task"))
        }
    }

    @Test
    func tasksRunThroughTheIntegratedShellWhenTheScriptsExist() async throws {
        try await withTempDir { directory in
            try await withTerminalCoverageSettings({ $0.useShellIntegration = true }) {
                let task = fixture.makeTask(command: "echo integrated-$((1+1))")
                let activeTask = CEActiveTask(task: task)
                let view = CEActiveTaskTerminalView(activeTask: activeTask)
                view.shellIntegrationDirectory = directory
                activeTask.output = view

                activeTask.run(workspaceURL: nil, shell: .zsh)

                try await eventually { activeTask.status == .finished }
                #expect(view.getBufferAsString().contains("integrated-2"))
                let userName = CurrentUser.getCurrentUser()?.name ?? "unknown"
                let copiedRcFile = directory.appending(path: "\(userName)-dreamder-zsh").appending(path: ".zshrc")
                #expect(FileManager.default.fileExists(atPath: copiedRcFile.path(percentEncoded: false)))
            }
        }
    }

    @Test
    func aTerminatedProcessWithoutAnExitCodeFailsTheTask() async throws {
        let activeTask = CEActiveTask(task: fixture.makeTask(command: "true"))
        let view = CEActiveTaskTerminalView(activeTask: activeTask)
        activeTask.output = view

        view.processTerminated(view.process, exitCode: nil)

        try await eventually { activeTask.status == .failed }
        #expect(view.getBufferAsString().contains("Failed to run Coverage Task"))
    }

    @Test
    func aFinishedTaskHasNoProcessLeftToSignal() async throws {
        try await withTerminalCoverageSettings(shellIntegration: false) {
            let activeTask = CEActiveTask(task: fixture.makeTask(command: "echo done-$((1+1))"))

            activeTask.run(workspaceURL: nil, shell: .zsh)

            try await eventually { activeTask.status == .finished }
            let output = try #require(activeTask.output)
            #expect(output.runningPID() == nil)
            #expect(output.getBufferAsString().contains("done-2"))
        }
    }

    @Test
    func aTaskFinishesEvenWhenALeftoverProcessKeepsTheTerminalOpen() async throws {
        try await withTerminalCoverageSettings(shellIntegration: false) {
            let task = fixture.makeTask(command: "trap '' HUP; sleep 600 & echo child-pid-$!-end")
            let activeTask = CEActiveTask(task: task)
            let view = CEActiveTaskTerminalView(activeTask: activeTask)
            view.drainPollInterval = .milliseconds(1)
            view.drainStallRounds = 5
            activeTask.output = view

            activeTask.run(workspaceURL: nil, shell: .zsh)

            try await eventually { TasksCoverageProcessProbe.announcedPID(in: view.getBufferAsString()) != nil }
            let child = try #require(TasksCoverageProcessProbe.announcedPID(in: view.getBufferAsString()))
            defer { kill(child, SIGKILL) }
            try await eventually { activeTask.status == .finished }
            #expect(view.getBufferAsString().contains("Finished running Coverage Task."))
        }
    }
}
