import Foundation
import Testing
@testable import Dreamder

extension GitCommandRunnerTests {
    @Test
    func writeCommandsInOneRepositoryNeverOverlap() async throws {
        try await withTempDir { directory in
            let probe = OverlapProbe(delay: .milliseconds(60))
            let commandRunner = runner(probe)
            try await withThrowingTaskGroup(of: Void.self) { group in
                for _ in 0..<6 {
                    group.addTask {
                        _ = try await commandRunner.run(
                            arguments: ["commit", "--message=x"],
                            workingDirectory: directory
                        )
                    }
                }
                try await group.waitForAll()
            }
            #expect(probe.completedRuns == 6)
            #expect(probe.maximumConcurrency == 1)
        }
    }

    @Test
    func readCommandsRunConcurrently() async throws {
        try await withTempDir { directory in
            let probe = OverlapProbe(delay: .milliseconds(300))
            let commandRunner = runner(probe)
            try await withThrowingTaskGroup(of: Void.self) { group in
                for _ in 0..<4 {
                    group.addTask {
                        _ = try await commandRunner.run(arguments: ["status"], workingDirectory: directory)
                    }
                }
                try await group.waitForAll()
            }
            #expect(probe.maximumConcurrency > 1)
        }
    }

    @Test
    func writeCommandsInDifferentRepositoriesRunConcurrently() async throws {
        try await withTempDir { directory in
            let first = directory.appending(path: "first")
            let second = directory.appending(path: "second")
            try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
            let probe = OverlapProbe(delay: .milliseconds(400))
            let commandRunner = runner(probe)
            try await withThrowingTaskGroup(of: Void.self) { group in
                for repository in [first, second] {
                    group.addTask {
                        _ = try await commandRunner.run(arguments: ["add", "--", "a"], workingDirectory: repository)
                    }
                }
                try await group.waitForAll()
            }
            #expect(probe.maximumConcurrency == 2)
        }
    }

    @Test
    func aCancelledWaiterNeverRunsItsCommand() async throws {
        try await withTempDir { directory in
            let probe = GatedProbe()
            let commandRunner = runner(probe)
            let gate = GitRepositoryGates.gate(for: directory)
            let first = Task {
                try await commandRunner.run(arguments: ["commit", "--message=a"], workingDirectory: directory)
            }
            var starts = probe.starts.makeAsyncIterator()
            await starts.next()
            #expect(await gate.pendingWaiters == 0)

            let second = Task {
                try await commandRunner.run(arguments: ["commit", "--message=b"], workingDirectory: directory)
            }
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(100))
            while await gate.pendingWaiters == 0, clock.now < deadline {
                try await Task.sleep(for: .milliseconds(5))
            }
            #expect(await gate.pendingWaiters == 1)
            second.cancel()
            probe.release()

            _ = try await first.value
            await #expect(throws: CancellationError.self) { try await second.value }
            #expect(probe.completedRuns == 1)
            #expect(await gate.pendingWaiters == 0)
        }
    }

    @Test
    func theExecutableIsResolvedOnceThroughXcrunAndCached() async throws {
        try await withTempDir { directory in
            let tool = directory.appending(path: "git")
            try Data("#!/bin/sh\n".utf8).write(to: tool)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: tool.path(percentEncoded: false)
            )
            let fake = FakeProcessRunner { _ in
                FakeProcessRunner.output(tool.path(percentEncoded: false) + "\n")
            }
            let locator = GitExecutableLocator(runner: fake)

            let first = await locator.executableURL()
            let second = await locator.executableURL()

            #expect(first.path(percentEncoded: false) == tool.path(percentEncoded: false))
            #expect(second == first)
            #expect(fake.invocations.count == 1)
            let invocation = try #require(fake.invocations.first)
            #expect(invocation.executable.path(percentEncoded: false) == "/usr/bin/xcrun")
            #expect(invocation.arguments == ["--find", "git"])
            #expect(invocation.timeout != nil)
        }
    }

    @Test
    func theExecutableFallsBackWhenXcrunFailsOrReturnsGarbage() async {
        let fallback = URL(fileURLWithPath: "/usr/bin/git")
        let failing = FakeProcessRunner { _ in FakeProcessRunner.output("", stderr: "xcrun: error", exitCode: 1) }
        #expect(await GitExecutableLocator(runner: failing, fallback: fallback).executableURL() == fallback)

        let garbage = FakeProcessRunner { _ in FakeProcessRunner.output("/nonexistent/dreamder/git\n") }
        #expect(await GitExecutableLocator(runner: garbage, fallback: fallback).executableURL() == fallback)

        let throwing = FakeProcessRunner { _ in throw ProcessRunnerError.timedOut(.seconds(10)) }
        #expect(await GitExecutableLocator(runner: throwing, fallback: fallback).executableURL() == fallback)
    }
}
