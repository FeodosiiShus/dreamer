import Foundation
import Testing
@testable import Dreamder

@Suite
struct ShellEnvironmentTests {
    private static func loginOutput(_ entries: [String]) -> String {
        entries.map { $0 + "\0" }.joined()
    }

    private func environment(
        output: String,
        exitCode: Int32 = 0,
        base: [String: String] = ["PATH": "/usr/bin", "FROM_BASE": "base"],
        timeout: Duration = .seconds(3)
    ) -> (ShellEnvironment, FakeProcessRunner) {
        let fake = FakeProcessRunner { _ in FakeProcessRunner.output(output, exitCode: exitCode) }
        let environment = ShellEnvironment(runner: fake, loadTimeout: timeout, baseEnvironment: { base })
        return (environment, fake)
    }

    @Test
    func environmentProvidesSearchPath() async {
        let environment = await ShellEnvironment.shared.load()
        guard let path = environment["PATH"] else {
            Issue.record("missing PATH")
            return
        }
        #expect(!path.isEmpty)
        #expect(path.contains("/usr/bin"))
    }

    @Test
    func environmentMatchesInteractiveLoginShellPath() async throws {
        let cachedPath = await ShellEnvironment.shared.load()["PATH"]
        let invocation = ProcessInvocation(
            executable: URL(fileURLWithPath: "/bin/zsh"),
            arguments: ["-lic", "print -r -- 'PATHDELIM:'${PATH}':PATHEND'"],
            timeout: .seconds(60)
        )
        let output = try await ProcessRunner().run(invocation).standardOutputText
        guard let start = output.range(of: "PATHDELIM:"),
              let end = output.range(of: ":PATHEND"),
              start.upperBound <= end.lowerBound else {
            Issue.record("unable to read login shell PATH")
            return
        }
        let loginPath = String(output[start.upperBound..<end.lowerBound])
        #expect(cachedPath == loginPath)
    }

    @Test
    func environmentReportsHomeDirectory() async {
        let environment = await ShellEnvironment.shared.load()
        #expect(environment["HOME"] == NSHomeDirectory())
    }

    @Test
    func sharedEnvironmentNeverContainsDyldVariables() async {
        let environment = await ShellEnvironment.shared.load()
        #expect(environment.keys.allSatisfy { !$0.hasPrefix("DYLD_") && !$0.hasPrefix("__XPC_DYLD_") })
    }

    @Test
    func loginShellOutputIsMergedOverTheBaseEnvironment() async throws {
        let output = Self.loginOutput([
            "PATH=/custom/bin:/usr/bin",
            "HOME=/Users/test",
            "EDITOR=vim",
            "OPTS=a=b",
            "SHLVL=3",
            "_=/usr/bin/env",
            "PWD=/somewhere",
            "OLDPWD=/before",
            "ZDOTDIR=/zdot",
            "DYLD_LIBRARY_PATH=/bad"
        ])
        let (shell, fake) = environment(
            output: output,
            base: ["PATH": "/usr/bin", "FROM_BASE": "base", "DYLD_FRAMEWORK_PATH": "/bad", "__XPC_DYLD_X": "/bad"]
        )

        let resolution = await shell.resolve()

        #expect(resolution.isLoginEnvironment)
        #expect(resolution.environment == [
            "PATH": "/custom/bin:/usr/bin",
            "HOME": "/Users/test",
            "EDITOR": "vim",
            "OPTS": "a=b",
            "FROM_BASE": "base"
        ])
        let invocation = try #require(fake.invocations.first)
        #expect(invocation.executable.path(percentEncoded: false) == "/bin/zsh")
        #expect(invocation.arguments == ["-lic", "env -0"])
        #expect(invocation.timeout == .seconds(3))
        #expect(invocation.standardInput == nil)
        #expect(invocation.environment["DYLD_FRAMEWORK_PATH"] == nil)
        #expect(invocation.environment["__XPC_DYLD_X"] == nil)
    }

    @Test
    func failedLoginShellFallsBackToWellKnownDirectories() async {
        let fake = FakeProcessRunner { _ in throw ProcessRunnerError.timedOut(.seconds(10)) }
        let shell = ShellEnvironment(runner: fake, baseEnvironment: {
            ["PATH": "/usr/bin:/bin", "DYLD_LIBRARY_PATH": "/bad"]
        })

        let resolution = await shell.resolve()

        #expect(!resolution.isLoginEnvironment)
        let path = resolution.environment["PATH"] ?? ""
        #expect(path.hasPrefix("/usr/bin:/bin:"))
        #expect(path.contains("/opt/homebrew/bin"))
        #expect(path.contains("/usr/local/bin"))
        #expect(resolution.environment["DYLD_LIBRARY_PATH"] == nil)
    }

    @Test
    func outputWithoutPathFallsBack() async {
        let (shell, _) = environment(output: Self.loginOutput(["FOO=bar"]), base: ["FROM_BASE": "base"])
        let resolution = await shell.resolve()
        #expect(!resolution.isLoginEnvironment)
        #expect(resolution.environment["FOO"] == nil)
        #expect(resolution.environment["FROM_BASE"] == "base")
    }

    @Test
    func emptyOutputFallsBack() async {
        let (shell, _) = environment(output: "")
        let resolution = await shell.resolve()
        #expect(!resolution.isLoginEnvironment)
    }

    @Test
    func theResultIsCachedAfterTheFirstLoad() async {
        let (shell, fake) = environment(output: Self.loginOutput(["PATH=/a"]))
        #expect(shell.cachedEnvironment == nil)
        _ = await shell.load()
        _ = await shell.load()
        #expect(shell.cachedEnvironment?["PATH"] == "/a")
        #expect(fake.invocations.count == 1)
    }

    @Test
    func concurrentCallersShareOneLoginShell() async {
        let (shell, fake) = environment(output: Self.loginOutput(["PATH=/a"]))
        shell.prepare()
        let paths = await withTaskGroup(of: String?.self) { group in
            for _ in 0..<20 {
                group.addTask { await shell.load()["PATH"] }
            }
            var collected: [String?] = []
            for await path in group {
                collected.append(path)
            }
            return collected
        }
        #expect(paths.allSatisfy { $0 == "/a" })
        #expect(fake.invocations.count == 1)
    }

    @Test
    func synchronousAccessReturnsTheFallbackWithoutBlockingAndStartsLoading() async throws {
        let (shell, fake) = environment(output: Self.loginOutput(["PATH=/login/bin", "LOGIN_ONLY=1"]))

        let immediate = shell.environment
        #expect(immediate["LOGIN_ONLY"] == nil)
        #expect(immediate["PATH"]?.contains("/opt/homebrew/bin") == true)

        let loaded = try await ProcessTestSupport.waitUntil { shell.cachedEnvironment != nil }
        #expect(loaded)
        #expect(shell.environment["LOGIN_ONLY"] == "1")
        #expect(fake.invocations.count == 1)
    }

    @Test
    func parseSkipsInvalidEntriesAndKeepsValuesContainingEquals() throws {
        var data = Data()
        for entry in ["PATH=/p", "1BAD=x", "BAD-NAME=x", "=empty", "novalue", "OPTS=a=b=c", "_UNDER=ok", "EMPTY="] {
            data.append(contentsOf: Array((entry + "\0").utf8))
        }
        data.append(contentsOf: [0x42, 0x3D, 0xFF, 0x00])

        let parsed = try #require(ShellEnvironment.parse(data, base: ["BASE": "1"]))

        #expect(parsed == ["PATH": "/p", "OPTS": "a=b=c", "_UNDER": "ok", "EMPTY": "", "BASE": "1"])
    }

    @Test
    func parseRejectsOutputWithoutEntriesOrPath() {
        #expect(ShellEnvironment.parse(Data(), base: ["PATH": "/p"]) == nil)
        #expect(ShellEnvironment.parse(Data("FOO=1\0".utf8), base: [:]) == nil)
        #expect(ShellEnvironment.parse(Data("PATH=\0".utf8), base: [:]) == nil)
        #expect(ShellEnvironment.parse(Data("FOO=1\0".utf8), base: ["PATH": "/p"]) != nil)
    }

    @Test
    func fallbackKeepsExistingPathOrderAndAppendsOnlyMissingDirectories() {
        let fallback = ShellEnvironment.fallbackEnvironment(base: [
            "PATH": "/usr/local/bin:/usr/bin",
            "DYLD_INSERT_LIBRARIES": "/bad",
            "KEEP": "1"
        ])
        let directories = (fallback["PATH"] ?? "").split(separator: ":").map(String.init)
        #expect(Array(directories.prefix(2)) == ["/usr/local/bin", "/usr/bin"])
        #expect(directories.filter { $0 == "/usr/local/bin" }.count == 1)
        #expect(directories.contains("/opt/homebrew/bin"))
        #expect(fallback["KEEP"] == "1")
        #expect(fallback["DYLD_INSERT_LIBRARIES"] == nil)
    }

    @Test
    func fallbackWorksWithoutAnyPath() {
        let fallback = ShellEnvironment.fallbackEnvironment(base: [:])
        #expect((fallback["PATH"] ?? "").contains("/opt/homebrew/bin"))
    }
}
