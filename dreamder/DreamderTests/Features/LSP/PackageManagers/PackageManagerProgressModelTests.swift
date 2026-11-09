import Foundation
import Testing
@testable import Dreamder

@MainActor
private func drain(_ model: PackageManagerProgressModel) async -> (statuses: [String], outputs: [String]) {
    model.finish()
    var statuses: [String] = []
    var outputs: [String] = []
    for await item in model.outputStream {
        switch item {
        case .status(let text): statuses.append(text)
        case .output(let text): outputs.append(text)
        }
    }
    return (statuses, outputs)
}

@MainActor
@Suite(.uiGate)
struct PackageManagerProgressModelTests {
    @Test
    func statusYieldsStatusItemsInOrder() async {
        let model = ScriptedProcesses().makeModel()
        model.status("first")
        model.status("second")
        let drained = await drain(model)
        #expect(drained.statuses == ["first", "second"])
        #expect(drained.outputs.isEmpty)
    }

    @Test
    func createDirectoryStructureBuildsIntermediateDirectories() async throws {
        try await withTempDir { directory in
            let target = directory.appending(path: "Language Servers/tool", directoryHint: .isDirectory)
            let model = ScriptedProcesses().makeModel()

            try model.createDirectoryStructure(for: target)

            var isDirectory: ObjCBool = false
            let targetPath = target.path(percentEncoded: false)
            #expect(FileManager.default.fileExists(atPath: targetPath, isDirectory: &isDirectory))
            #expect(isDirectory.boolValue)
            let drained = await drain(model)
            #expect(drained.statuses == ["Creating directory: \(target.path(percentEncoded: false))"])
        }
    }

    @Test
    func createDirectoryStructureReplacesAnExistingInstallation() async throws {
        try await withTempDir { directory in
            let target = directory.appending(path: "tool", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            let leftover = target.appending(path: "old.txt")
            try Data("old".utf8).write(to: leftover)
            let model = ScriptedProcesses().makeModel()

            try model.createDirectoryStructure(for: target)

            #expect(!FileManager.default.fileExists(atPath: leftover.path(percentEncoded: false)))
            #expect(FileManager.default.fileExists(atPath: target.path(percentEncoded: false)))
            let drained = await drain(model)
            #expect(drained.statuses == [
                "Removing existing installation.",
                "Creating directory: \(target.path(percentEncoded: false))"
            ])
        }
    }

    @Test
    func createDirectoryStructureFailsBelowARegularFile() async throws {
        try withTempDir { directory in
            let blocker = directory.appending(path: "blocker")
            try Data("file".utf8).write(to: blocker)
            let model = ScriptedProcesses().makeModel()

            #expect(throws: (any Error).self) {
                try model.createDirectoryStructure(for: blocker.appending(path: "child"))
            }
        }
    }

    @Test
    func runPassesTheArgvLiterallyThroughEnvInTheGivenDirectory() async throws {
        let shell = ScriptedProcesses { _ in FakeProcessRunner.output("line one\nline two\n") }
        let model = shell.makeModel()
        let directory = URL(filePath: "/tmp/some dir", directoryHint: .isDirectory)

        let lines = try await model.run(["npm", "install", "left-pad"], in: directory)

        #expect(lines == ["line one", "line two"])
        let invocation = try #require(shell.invocations.first)
        #expect(shell.invocations.count == 1)
        #expect(invocation.executable == PackageManagerProgressModel.envExecutable)
        #expect(invocation.arguments == ["npm", "install", "left-pad"])
        #expect(invocation.workingDirectory == directory)
        let drained = await drain(model)
        #expect(drained.statuses == ["npm install left-pad"])
        #expect(drained.outputs == ["line one", "line two"])
    }

    @Test
    func runWithoutADirectoryLeavesTheWorkingDirectoryUnset() async throws {
        let shell = ScriptedProcesses()
        let model = shell.makeModel()

        let lines = try await model.run(["go", "version"])

        #expect(lines.isEmpty)
        #expect(shell.workingDirectories == [nil])
        #expect(shell.arguments == [["go", "version"]])
    }

    @Test
    func runUsesTheLoginEnvironmentAndOverridesWin() async throws {
        let shell = ScriptedProcesses()
        let model = shell.makeModel()

        try await model.run(["go", "install", "example.com/tool@v1"])
        try await model.run(
            ["go", "install", "example.com/tool@v1"],
            environment: ["GOBIN": "/tmp/pkg/bin", "PATH": "/override"]
        )

        let plain = try #require(shell.invocations.first)
        let overridden = try #require(shell.invocations.last)
        #expect(plain.environment["PATH"] == "/usr/bin:/bin")
        #expect(plain.environment["HOME"] == "/Users/tester")
        #expect(plain.environment["GOBIN"] == nil)
        #expect(overridden.environment["GOBIN"] == "/tmp/pkg/bin")
        #expect(overridden.environment["PATH"] == "/override")
        #expect(overridden.environment["HOME"] == "/Users/tester")
    }

    @Test
    func runYieldsStandardOutputThenStandardErrorLinesInOrder() async throws {
        let shell = ScriptedProcesses { _ in
            FakeProcessRunner.output("out one\nout two\n", stderr: "err one\nerr two")
        }
        let model = shell.makeModel()

        let lines = try await model.run(["cargo", "--version"])

        #expect(lines == ["out one", "out two", "err one", "err two"])
        let drained = await drain(model)
        #expect(drained.statuses == ["cargo --version"])
        #expect(drained.outputs == ["out one", "out two", "err one", "err two"])
    }

    @Test
    func runPropagatesTheExitStatusAfterStreamingItsOutput() async {
        let shell = ScriptedProcesses { _ in FakeProcessRunner.output("partial\n", stderr: "boom\n", exitCode: 3) }
        let model = shell.makeModel()

        await #expect(throws: ShellClientError.taskTerminated(code: 3)) {
            try await model.run(["make", "all"])
        }

        let drained = await drain(model)
        #expect(drained.statuses == ["make all"])
        #expect(drained.outputs == ["partial", "boom"])
    }

    @Test
    func runThrowsWhenTheProcessIsTerminatedByASignal() async {
        let shell = ScriptedProcesses { _ in
            ProcessOutput(exitCode: 0, terminatedBySignal: true, standardOutput: Data("cut\n".utf8))
        }
        let model = shell.makeModel()

        await #expect(throws: ShellClientError.taskTerminated(code: 0)) {
            try await model.run(["npm", "install"])
        }

        let drained = await drain(model)
        #expect(drained.outputs == ["cut"])
    }

    @Test
    func runPropagatesALaunchFailure() async {
        let failure = ProcessRunnerError.launchFailed(executable: "/usr/bin/env", reason: "denied")
        let shell = ScriptedProcesses { _ in throw failure }
        let model = shell.makeModel()

        await #expect(throws: failure) {
            try await model.run(["git", "--version"])
        }

        let drained = await drain(model)
        #expect(drained.statuses == ["git --version"])
        #expect(drained.outputs.isEmpty)
    }

    @Test(arguments: [
        ["sh", "-c", "touch x"],
        ["rm", "-rf", "/"],
        ["bash"],
        ["curl", "https://example.com"],
        ["zsh"],
        ["-rf"],
        ["./make"],
        ["../npm"],
        ["bin/npm"],
        ["NPM"],
        [""],
        [" npm"]
    ])
    func runRejectsNonAllowlistedExecutablesWithoutRunningAnything(argv: [String]) async {
        let shell = ScriptedProcesses()
        let model = shell.makeModel()

        await #expect {
            try await model.run(argv)
        } throws: { isUnsafeValue($0, argv[0]) }

        #expect(shell.invocations.isEmpty)
        let drained = await drain(model)
        #expect(drained.statuses.isEmpty)
        #expect(drained.outputs.isEmpty)
    }

    @Test
    func runRejectsAnEmptyArgvWithoutRunningAnything() async {
        let shell = ScriptedProcesses()
        let model = shell.makeModel()

        await #expect {
            try await model.run([])
        } throws: { isUnsafeValue($0, "") }

        #expect(shell.invocations.isEmpty)
    }

    @Test(arguments: [
        "npm", "cargo", "go", "git", "python", "python3", "pip3", "tar", "gunzip",
        "make", "cmake", "yarn", "pnpm", "dotnet", "swift", "zig",
        "/usr/bin/python3", "/tmp/pkg dir/venv/bin/pip"
    ])
    func runAllowsAllowlistedAndAbsoluteExecutables(executable: String) async throws {
        let shell = ScriptedProcesses()
        let model = shell.makeModel()

        try await model.run([executable, "--version"])

        #expect(shell.arguments == [[executable, "--version"]])
    }

    @Test(arguments: ["; rm -rf ~", "$(id)", "line\nbreak", "`id`", "a && b", "'quoted'", "\"dq\"", "x\u{0}y"])
    func runDeliversInjectionPayloadsAsOneVerbatimArgument(payload: String) async throws {
        let shell = ScriptedProcesses()
        let model = shell.makeModel()

        try await model.run(["npm", "install", payload, "--flag"])

        #expect(shell.arguments == [["npm", "install", payload, "--flag"]])
        let invocation = try #require(shell.invocations.first)
        #expect(invocation.executable == PackageManagerProgressModel.envExecutable)
    }
}

nonisolated private func isUnsafeValue(_ error: any Error, _ value: String) -> Bool {
    if case PackageManagerError.unsafeValue(let payload) = error {
        return payload == value
    }
    return false
}
