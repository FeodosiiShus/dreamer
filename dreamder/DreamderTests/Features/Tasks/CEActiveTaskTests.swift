//
//  CEActiveTaskTests.swift
//  DreamderTests
//
//  Created by Tommy Ludwig on 08.07.24.
//

import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized)
class CEActiveTaskTests {
    var task: CETask
    var activeTask: CEActiveTask
    private let isolatedZshDirectory: URL

    init() throws {
        isolatedZshDirectory = try makeTemporaryDirectory(label: "zdotdir")
        for name in [".zshenv", ".zprofile", ".zshrc", ".zlogin"] {
            try "".write(to: isolatedZshDirectory.appending(path: name), atomically: true, encoding: .utf8)
        }
        task = CETask(
            name: "Test Task",
            command: "echo $STATE",
            environmentVariables: [
                CETask.EnvironmentVariable(key: "STATE", value: "Testing"),
                CETask.EnvironmentVariable(key: "ZDOTDIR", value: isolatedZshDirectory.path(percentEncoded: false))
            ]
        )
        activeTask = CEActiveTask(task: task)
    }

    deinit {
        try? FileManager.default.removeItem(at: isolatedZshDirectory)
    }

    @Test
    func testInitialization() throws {
        #expect(activeTask.task == task, "Active task should be initialized with the provided CETask.")
    }

    @Test(arguments: [Shell.zsh, Shell.bash])
    func testRunMethod(_ shell: Shell) async throws {
        activeTask.run(workspaceURL: nil, shell: shell)
        await waitForExpectation(timeout: .seconds(90)) {
            activeTask.status == .running
        } onTimeout: {
            Issue.record("Task never started. \(activeTask.status)")
        }
        await activeTask.waitForExit()

        await waitForExpectation(timeout: .seconds(90)) {
            activeTask.status == .finished
        } onTimeout: {
            Issue.record("Status never changed to finished. \(activeTask.status)")
        }

        let output = try #require(activeTask.output)
        await waitForExpectation(timeout: .seconds(90)) {
            output.getBufferAsString().contains("Testing")
        } onTimeout: {
            Issue.record("Output never contained the environment value. \(output.getBufferAsString())")
        }
    }

    @Test(arguments: [Shell.zsh, Shell.bash])
    func testHandleProcessFinished(_ shell: Shell) async throws {
        task.command = "aNon-existentCommand"
        activeTask.run(workspaceURL: nil, shell: shell)
        await activeTask.waitForExit()

        await waitForExpectation(timeout: .seconds(90)) {
            activeTask.status == .failed
        } onTimeout: {
            Issue.record("Status never changed to failed. \(activeTask.status)")
        }
    }

    @Test(arguments: [Shell.zsh, Shell.bash])
    func testClearOutput(_ shell: Shell) async throws {
        activeTask.run(workspaceURL: nil, shell: shell)
        await activeTask.waitForExit()

        await waitForExpectation(timeout: .seconds(90)) {
            activeTask.status == .finished
        } onTimeout: {
            Issue.record("Status never changed to finished.")
        }

        #expect(
            activeTask.output?.getBufferAsString().isEmpty == false,
            "Task output should not be empty after task completion."
        )
        activeTask.clearOutput()

        await waitForExpectation {
            activeTask.output?.getBufferAsString().isEmpty == true
        } onTimeout: {
            Issue.record("Task output should be empty after clearOutput is called.")
        }
    }

    @Test(arguments: [Shell.zsh, Shell.bash])
    func outputIsCompleteWhenTheTaskFinishes(_ shell: Shell) async throws {
        task.command = "for i in $(seq 1 120); do echo line-$i; done; echo FINAL-MARKER"
        activeTask.run(workspaceURL: nil, shell: shell)

        await waitForExpectation(timeout: .seconds(90)) {
            activeTask.status == .finished
        } onTimeout: {
            Issue.record("Status never changed to finished. \(activeTask.status)")
        }

        let output = try #require(activeTask.output).getBufferAsString()
        #expect(output.contains("FINAL-MARKER"))
        #expect(output.contains("line-120"))
    }
}
