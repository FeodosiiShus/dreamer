import Foundation
import Testing
@testable import Dreamder

@Suite
struct ShellEnvironmentTests {
    @Test
    func environmentProvidesSearchPath() {
        let environment = ShellEnvironment.shared.environment
        guard let path = environment["PATH"] else {
            Issue.record("missing PATH")
            return
        }
        #expect(!path.isEmpty)
        #expect(path.contains("/usr/bin"))
    }

    @Test
    func environmentMatchesInteractiveLoginShellPath() async throws {
        let cachedPath = await Task.detached { ShellEnvironment.shared.environment["PATH"] }.value
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lic", "print -r -- 'PATHDELIM:'${PATH}':PATHEND'"]
        process.standardError = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)
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
    func environmentReportsHomeDirectory() {
        let environment = ShellEnvironment.shared.environment
        #expect(environment["HOME"] == NSHomeDirectory())
    }

    @Test
    func shellClientUsesNonInteractiveShell() throws {
        let output = try ShellClient.live().run("print -r -- $-")
        #expect(!output.contains("i"))
    }

    @Test
    func shellClientMergesStandardErrorIntoOutput() throws {
        let output = try ShellClient.live().run("echo out; echo err 1>&2")
        #expect(output.contains("out"))
        #expect(output.contains("err"))
    }

    @Test
    func shellClientResolvesLoginTools() throws {
        let gitPath = try ShellClient.live().run("command -v git")
        #expect(gitPath.contains("git"))

        let version = try ShellClient.live().run("git --version")
        #expect(version.contains("git version"))
    }
}
