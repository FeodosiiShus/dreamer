import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct CETaskWorkingDirectoryQuotingTests {
    nonisolated static let hostileDirectoryNames = [
        "plain",
        "a b",
        "a$b",
        "$(touch pwned)",
        "a`touch pwned`b",
        "it's",
        "say \"hi\"",
        "multi\nline",
        "trailing\\",
        "back\\\"slash",
        "semi;colon && pipe | redirect > glob *",
        "~tilde",
        "-leading-dash",
        "ünï 🙂"
    ]

    private func run(_ task: CETask, in root: URL) async throws -> ProcessOutput {
        try await ProcessRunner().run(ProcessTestSupport.shell(task.fullCommand, workingDirectory: root))
    }

    private func printWorkingDirectory(
        of name: String,
        in root: URL
    ) async throws -> (path: String, output: ProcessOutput) {
        let path = root.path + "/" + name
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: false)
        let task = CETask(name: "Probe", workingDirectory: path, command: "pwd")
        return (path, try await run(task, in: root))
    }

    @Test(arguments: hostileDirectoryNames)
    func theShellEntersTheExactDirectory(name: String) async throws {
        try await withTempDir { root in
            let result = try await printWorkingDirectory(of: name, in: root)

            #expect(result.output.succeeded)
            #expect(result.output.standardErrorText.isEmpty)
            #expect(result.output.standardOutputText == result.path + "\n")
            let leftovers = try FileManager.default.contentsOfDirectory(atPath: root.path)
            #expect(!leftovers.contains("pwned"))
        }
    }

    @Test
    func aMissingWorkingDirectoryStopsTheCommandFromRunning() async throws {
        try await withTempDir { root in
            let missing = root.path + "/no $such `dir`"
            let task = CETask(name: "Probe", workingDirectory: missing, command: "printf ran")

            let output = try await run(task, in: root)

            #expect(!output.succeeded)
            #expect(output.standardOutputText.isEmpty)
        }
    }

    @Test
    func aTaskWithoutWorkingDirectoryRunsInTheInheritedDirectory() async throws {
        try await withTempDir { root in
            let task = CETask(name: "Probe", command: "pwd")

            let output = try await run(task, in: root)

            #expect(output.succeeded)
            #expect(output.standardOutputText.hasSuffix("\n"))
        }
    }

    @Test
    func aRelativeWorkingDirectoryStartingWithADashIsNotReadAsAnOption() async throws {
        try await withTempDir { root in
            let directory = root.path + "/-rf"
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: false)
            try Data().write(to: URL(fileURLWithPath: directory + "/inside-marker"))
            let task = CETask(name: "Probe", workingDirectory: "-rf", command: "ls")

            let output = try await run(task, in: root)

            #expect(task.fullCommand == "cd -- -rf && ls")
            #expect(output.succeeded)
            #expect(output.standardOutputText == "inside-marker\n")
        }
    }
}
