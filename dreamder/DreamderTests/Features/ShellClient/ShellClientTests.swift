import Foundation
import Testing
@testable import Dreamder

@Suite
struct ShellClientTests {
    private static func client(
        extraEnvironment: [String: String] = [:],
        runner: any ProcessRunning = ProcessRunner()
    ) -> ShellClient {
        var entries = ["PATH=/usr/bin:/bin:/usr/sbin:/sbin"]
        entries += extraEnvironment.map { "\($0.key)=\($0.value)" }
        let output = entries.map { $0 + "\0" }.joined()
        let loginShell = FakeProcessRunner { _ in FakeProcessRunner.output(output) }
        let environment = ShellEnvironment(runner: loginShell, baseEnvironment: { [:] })
        return ShellClient(runner: runner, shellEnvironment: environment)
    }

    @Test
    func runReportsExitCodeAndKeepsStreamsSeparate() async throws {
        let result = try await Self.client().run("echo out; echo err 1>&2; exit 4")
        #expect(result.exitCode == 4)
        #expect(result.standardOutput == "out\n")
        #expect(result.standardError == "err\n")
        #expect(!result.succeeded)
        #expect(!result.terminatedBySignal)
    }

    @Test
    func successfulCommandsSucceed() async throws {
        let result = try await Self.client().run("print -r -- hello")
        #expect(result.succeeded)
        #expect(result.standardOutput == "hello\n")
        #expect(result.standardError.isEmpty)
    }

    @Test
    func shellUsesNonInteractiveShell() async throws {
        let result = try await Self.client().run("print -r -- $-")
        #expect(!result.standardOutput.contains("i"))
    }

    @Test
    func shellSyntaxIsSupportedForPackageManagerCommands() async throws {
        try await withTempDir { directory in
            let path = directory.path(percentEncoded: false)
            let result = try await Self.client().run("cd \"\(path)\" && pwd -P && echo $((6 * 7))")
            let lines = result.standardOutput.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            #expect(lines.count == 3)
            #expect(URL(filePath: lines[0]).resolvingSymlinksInPath().path == directory.resolvingSymlinksInPath().path)
            #expect(Array(lines.dropFirst()) == ["42", ""])
        }
    }

    @Test
    func commandsReceiveTheResolvedLoginEnvironment() async throws {
        let client = Self.client(extraEnvironment: ["DREAMDER_PROBE": "from login shell"])
        let result = try await client.run("print -r -- $DREAMDER_PROBE")
        #expect(result.standardOutput == "from login shell\n")
    }

    @Test
    func standardInputIsClosed() async throws {
        let result = try await Self.client().run("cat; print -r -- done")
        #expect(result.standardOutput == "done\n")
    }

    @Test
    func shellClientResolvesLoginTools() async throws {
        let gitPath = try await ShellClient.live().run("command -v git")
        #expect(gitPath.standardOutput.contains("git"))

        let version = try await ShellClient.live().run("git --version")
        #expect(version.standardOutput.contains("git version"))
    }

    @Test
    func runPassesAnEnvironmentWithoutDyldVariables() async throws {
        let fake = FakeProcessRunner { _ in FakeProcessRunner.output("") }
        let client = Self.client(extraEnvironment: ["DYLD_LIBRARY_PATH": "/bad", "KEEP": "1"], runner: fake)
        _ = try await client.run("true")

        let invocation = try #require(fake.invocations.first)
        #expect(invocation.executable.path(percentEncoded: false) == "/bin/zsh")
        #expect(invocation.arguments == ["-c", "true"])
        #expect(invocation.environment["KEEP"] == "1")
        #expect(invocation.environment["DYLD_LIBRARY_PATH"] == nil)
    }

    @Test
    func runAsyncYieldsMergedOutputInOrder() async throws {
        var lines: [String] = []
        for try await line in Self.client().runAsync("echo one; echo two 1>&2; echo three") {
            lines.append(line)
        }
        #expect(lines == ["one", "two", "three"])
    }

    @Test
    func runAsyncThrowsTheExitCodeAfterTheLines() async {
        var lines: [String] = []
        do {
            for try await line in Self.client().runAsync("echo before; exit 7") {
                lines.append(line)
            }
            Issue.record("expected the stream to fail")
        } catch {
            #expect(error as? ShellClientError == .taskTerminated(code: 7))
        }
        #expect(lines == ["before"])
    }

    @Test
    func runAsyncWaitsForTheExitStatusAfterTheOutputEnded() async {
        var lines: [String] = []
        do {
            for try await line in Self.client().runAsync("echo started; sleep 0.3; exit 3") {
                lines.append(line)
            }
            Issue.record("expected the stream to fail")
        } catch {
            #expect(error as? ShellClientError == .taskTerminated(code: 3))
        }
        #expect(lines == ["started"])
    }

    @Test
    func runAsyncSplitsCarriageReturnProgress() async throws {
        var lines: [String] = []
        for try await line in Self.client().runAsync("printf '10%%\\r50%%\\r100%%\\n'") {
            lines.append(line)
        }
        #expect(lines == ["10%", "50%", "100%"])
    }

    @Test
    func cancellingTheConsumerTerminatesTheCommand() async throws {
        try await withTempDir { directory in
            let pidFile = directory.appending(path: "pid")
            let command = "echo $$ > \"\(pidFile.path(percentEncoded: false))\"; echo started; exec sleep 60"
            let client = Self.client()
            let consumer = Task {
                for try await line in client.runAsync(command) where line == "started" {
                    try await Task.sleep(for: .seconds(60))
                }
            }
            let started = try await ProcessTestSupport.waitUntil(timeout: .seconds(90)) {
                ProcessTestSupport.readProcessIdentifier(from: pidFile) != nil
            }
            #expect(started)
            let processIdentifier = try #require(ProcessTestSupport.readProcessIdentifier(from: pidFile))

            consumer.cancel()
            _ = await consumer.result

            let died = try await ProcessTestSupport.waitUntil(timeout: .seconds(20)) {
                !ProcessTestSupport.isAlive(processIdentifier)
            }
            #expect(died)
        }
    }
}
