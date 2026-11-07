import Foundation
import Testing
@testable import Dreamder

@Suite
struct ProcessRunnerTests {
    private let runner = ProcessRunner()

    @Test
    func capturesExitCodeAndSeparateStreams() async throws {
        let output = try await runner.run(ProcessTestSupport.shell("printf out; printf err >&2; exit 3"))
        #expect(output.exitCode == 3)
        #expect(!output.terminatedBySignal)
        #expect(output.standardOutputText == "out")
        #expect(output.standardErrorText == "err")
        #expect(!output.succeeded)
    }

    @Test
    func zeroExitIsASuccess() async throws {
        let output = try await runner.run(ProcessTestSupport.shell("exit 0"))
        #expect(output.succeeded)
        #expect(output.standardOutput.isEmpty)
        #expect(output.standardError.isEmpty)
    }

    @Test
    func reportsDeathBySignal() async throws {
        let output = try await runner.run(ProcessTestSupport.shell("kill -9 $$"))
        #expect(output.terminatedBySignal)
        #expect(output.exitCode == 9)
        #expect(!output.succeeded)
    }

    @Test
    func largeOutputOnBothStreamsDoesNotDeadlock() async throws {
        let script = "head -c 300000 /dev/zero | tr '\\0' x >&2; head -c 200000 /dev/zero | tr '\\0' y"
        let output = try await runner.run(ProcessTestSupport.shell(script))
        #expect(output.exitCode == 0)
        #expect(output.standardError.count == 300_000)
        #expect(output.standardOutput.count == 200_000)
        #expect(output.standardError.allSatisfy { $0 == UInt8(ascii: "x") })
        #expect(output.standardOutput.allSatisfy { $0 == UInt8(ascii: "y") })
    }

    @Test
    func standardInputIsDeliveredAndClosed() async throws {
        let payload = Data((0..<1_000_000).map { UInt8(truncatingIfNeeded: $0 % 251) })
        let invocation = ProcessInvocation(
            executable: URL(fileURLWithPath: "/bin/cat"),
            environment: ProcessTestSupport.minimalEnvironment,
            standardInput: payload,
            timeout: .seconds(60)
        )
        let output = try await runner.run(invocation)
        #expect(output.exitCode == 0)
        #expect(output.standardOutput == payload)
    }

    @Test
    func emptyStandardInputIsEndOfFileImmediately() async throws {
        let invocation = ProcessInvocation(
            executable: URL(fileURLWithPath: "/bin/cat"),
            environment: ProcessTestSupport.minimalEnvironment,
            standardInput: Data(),
            timeout: .seconds(30)
        )
        let output = try await runner.run(invocation)
        #expect(output.exitCode == 0)
        #expect(output.standardOutput.isEmpty)
    }

    @Test
    func absentStandardInputIsDevNull() async throws {
        let invocation = ProcessInvocation(
            executable: URL(fileURLWithPath: "/bin/cat"),
            environment: ProcessTestSupport.minimalEnvironment,
            timeout: .seconds(30)
        )
        let output = try await runner.run(invocation)
        #expect(output.exitCode == 0)
        #expect(output.standardOutput.isEmpty)
    }

    @Test
    func childReceivesTheGivenEnvironmentAndNothingElse() async throws {
        let script = "printf '%s|%s|%s' \"$KEEP\" \"${TMPDIR-unset}\" \"${__CF_USER_TEXT_ENCODING-unset}\""
        var environment = ProcessTestSupport.minimalEnvironment
        environment["KEEP"] = "value with spaces"
        let output = try await runner.run(ProcessTestSupport.shell(script, environment: environment))
        #expect(output.standardOutputText == "value with spaces|unset|unset")
    }

    @Test
    func dyldVariablesNeverReachTheChild() async throws {
        let script = "printf '%s|%s|%s' \"${DYLD_LIBRARY_PATH-unset}\" \"${DYLD_INSERT_LIBRARIES-unset}\" \"$KEEP\""
        var environment = ProcessTestSupport.minimalEnvironment
        environment["DYLD_LIBRARY_PATH"] = "/nonexistent/lib"
        environment["DYLD_INSERT_LIBRARIES"] = "/nonexistent/lib.dylib"
        environment["__XPC_DYLD_FRAMEWORK_PATH"] = "/nonexistent/frameworks"
        environment["KEEP"] = "kept"
        let output = try await runner.run(ProcessTestSupport.shell(script, environment: environment))
        #expect(output.standardOutputText == "unset|unset|kept")
    }

    @Test
    func runsInTheGivenWorkingDirectory() async throws {
        try await withTempDir { directory in
            let output = try await runner.run(ProcessTestSupport.shell("pwd -P", workingDirectory: directory))
            let reported = output.standardOutputText.trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(URL(filePath: reported).resolvingSymlinksInPath().path == directory.resolvingSymlinksInPath().path)
        }
    }

    @Test
    func missingExecutableThrowsLaunchFailure() async {
        let missing = URL(fileURLWithPath: "/nonexistent/dreamder-missing-binary")
        do {
            _ = try await runner.run(ProcessInvocation(executable: missing, environment: [:]))
            Issue.record("expected a launch failure")
        } catch ProcessRunnerError.launchFailed(let executable, let reason) {
            #expect(executable == "/nonexistent/dreamder-missing-binary")
            #expect(!reason.isEmpty)
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test
    func missingWorkingDirectoryThrowsLaunchFailure() async {
        let invocation = ProcessTestSupport.shell(
            "exit 0",
            workingDirectory: URL(fileURLWithPath: "/nonexistent/dreamder-missing-directory")
        )
        await #expect {
            try await runner.run(invocation)
        } throws: { error in
            if case ProcessRunnerError.launchFailed = error { return true }
            return false
        }
    }

    @Test
    func timeoutTerminatesTheChildAndThrows() async throws {
        let clock = ContinuousClock()
        let started = clock.now
        let timeout = Duration.milliseconds(300)
        await #expect(throws: ProcessRunnerError.timedOut(timeout)) {
            try await runner.run(ProcessTestSupport.shell("exec sleep 60", timeout: timeout))
        }
        #expect(clock.now - started < .seconds(30))
    }

    @Test
    func commandFinishingBeforeTheTimeoutIsNotAffected() async throws {
        let output = try await runner.run(ProcessTestSupport.shell("printf done", timeout: .seconds(30)))
        #expect(output.standardOutputText == "done")
    }

    @Test
    func cancellationTerminatesTheChild() async throws {
        try await withTempDir { directory in
            let pidFile = directory.appending(path: "pid")
            let invocation = ProcessTestSupport.shell(
                "echo $$ > \"$1\"; exec sleep 60",
                arguments: [pidFile.path(percentEncoded: false)]
            )
            let task = Task { try await runner.run(invocation) }

            let started = try await ProcessTestSupport.waitUntil {
                ProcessTestSupport.readProcessIdentifier(from: pidFile) != nil
            }
            #expect(started)
            let processIdentifier = try #require(ProcessTestSupport.readProcessIdentifier(from: pidFile))

            task.cancel()
            let result = await task.result
            #expect(throws: CancellationError.self) { try result.get() }

            let died = try await ProcessTestSupport.waitUntil { !ProcessTestSupport.isAlive(processIdentifier) }
            #expect(died)
        }
    }

    @Test
    func cancellingBeforeStartNeverRunsTheCommand() async throws {
        try await withTempDir { directory in
            let marker = directory.appending(path: "ran")
            let invocation = ProcessTestSupport.shell(
                "touch \"$1\"",
                arguments: [marker.path(percentEncoded: false)]
            )
            let task = Task {
                withUnsafeCurrentTask { $0?.cancel() }
                return try await runner.run(invocation)
            }
            let result = await task.result
            #expect(throws: CancellationError.self) { try result.get() }
            try await Task.sleep(for: .milliseconds(200))
            #expect(!FileManager.default.fileExists(atPath: marker.path(percentEncoded: false)))
        }
    }

    @Test
    func invalidUTF8IsDecodedLossily() async throws {
        let output = try await runner.run(ProcessTestSupport.shell("printf '\\377abc'"))
        #expect(output.standardOutput == Data([0xFF, 0x61, 0x62, 0x63]))
        #expect(output.standardOutputText == "\u{FFFD}abc")
    }

    @Test
    func manyConcurrentProcessesDoNotStarveEachOther() async throws {
        let count = 48
        let results = try await withThrowingTaskGroup(of: String.self) { group in
            for index in 0..<count {
                group.addTask {
                    let output = try await ProcessRunner().run(
                        ProcessTestSupport.shell("sleep 0.2; printf %s \"$1\"", arguments: ["\(index)"])
                    )
                    return output.standardOutputText
                }
            }
            var collected: [String] = []
            for try await result in group {
                collected.append(result)
            }
            return collected
        }
        #expect(results.sorted() == (0..<count).map(String.init).sorted())
    }

    @Test
    func streamYieldsLinesPerStreamAndTheExit() async throws {
        let script = "printf 'one\\rtwo\\n\\nthree'; printf 'err1\\nerr2\\n' >&2; exit 2"
        var standardOutput: [String] = []
        var standardError: [String] = []
        var exit: ProcessEvent?
        for try await event in runner.stream(ProcessTestSupport.shell(script)) {
            switch event {
            case .line(.standardOutput, let line): standardOutput.append(line)
            case .line(.standardError, let line): standardError.append(line)
            case .exit: exit = event
            }
        }
        #expect(standardOutput == ["one", "two", "three"])
        #expect(standardError == ["err1", "err2"])
        #expect(exit == .exit(code: 2, terminatedBySignal: false))
    }

    @Test
    func streamDecodesMultiByteCharactersSplitAcrossReads() async throws {
        let script = "printf '\\303'; sleep 0.3; printf '\\251\\n'"
        var lines: [String] = []
        for try await event in runner.stream(ProcessTestSupport.shell(script)) {
            if case .line(.standardOutput, let line) = event {
                lines.append(line)
            }
        }
        #expect(lines == ["é"])
    }

    @Test
    func abandoningTheStreamTerminatesTheChild() async throws {
        try await withTempDir { directory in
            let pidFile = directory.appending(path: "pid")
            let invocation = ProcessTestSupport.shell(
                "echo $$ > \"$1\"; echo started; exec sleep 60",
                arguments: [pidFile.path(percentEncoded: false)]
            )
            for try await event in runner.stream(invocation) {
                if case .line(_, "started") = event {
                    break
                }
            }
            let processIdentifier = try #require(ProcessTestSupport.readProcessIdentifier(from: pidFile))
            let died = try await ProcessTestSupport.waitUntil { !ProcessTestSupport.isAlive(processIdentifier) }
            #expect(died)
        }
    }

    @Test
    func defaultStreamImplementationReplaysTheCompletedRun() async throws {
        let fake = FakeProcessRunner { _ in
            FakeProcessRunner.output("a\nb\n", stderr: "warn\n", exitCode: 5)
        }
        var events: [ProcessEvent] = []
        for try await event in fake.stream(ProcessTestSupport.shell("ignored")) {
            events.append(event)
        }
        #expect(events == [
            .line(.standardOutput, "a"),
            .line(.standardOutput, "b"),
            .line(.standardError, "warn"),
            .exit(code: 5, terminatedBySignal: false)
        ])
    }
}

@Suite
struct ProcessSupportTypesTests {
    @Test
    func sanitizedDropsDyldAndXpcDyldVariablesOnly() {
        let environment = [
            "DYLD_LIBRARY_PATH": "/a",
            "DYLD_FRAMEWORK_PATH": "/b",
            "DYLD_INSERT_LIBRARIES": "/c",
            "__XPC_DYLD_LIBRARY_PATH": "/d",
            "__XPC_DYLD_FRAMEWORK_PATH": "/e",
            "PATH": "/usr/bin",
            "HOME": "/Users/test",
            "MY_DYLD_NOTE": "kept",
            "dyld_lowercase": "kept"
        ]
        #expect(ProcessEnvironment.sanitized(environment) == [
            "PATH": "/usr/bin",
            "HOME": "/Users/test",
            "MY_DYLD_NOTE": "kept",
            "dyld_lowercase": "kept"
        ])
    }

    @Test
    func sanitizedKeepsAnEmptyEnvironmentEmpty() {
        #expect(ProcessEnvironment.sanitized([:]).isEmpty)
    }

    @Test
    func processOutputDecodesText() {
        let output = ProcessOutput(
            exitCode: 0,
            terminatedBySignal: false,
            standardOutput: Data("héllo".utf8),
            standardError: Data([0x66, 0xFF])
        )
        #expect(output.standardOutputText == "héllo")
        #expect(output.standardErrorText == "f\u{FFFD}")
    }

    @Test
    func lineSplitterBuffersPartialLinesAndSplitsOnBothTerminators() {
        var splitter = ProcessLineSplitter()
        #expect(splitter.append(Data("par".utf8)).isEmpty)
        #expect(splitter.append(Data("tial\r\nnext\rlast".utf8)) == ["partial", "next"])
        #expect(splitter.finish() == "last")
        #expect(splitter.finish() == nil)
    }

    @Test
    func lineSplitterKeepsMultiByteCharactersTogetherAcrossChunks() {
        var splitter = ProcessLineSplitter()
        #expect(splitter.append(Data([0xE2, 0x82])).isEmpty)
        #expect(splitter.append(Data([0xAC, 0x0A])) == ["€"])
    }

    @Test
    func lineSplitterOmitsEmptyLines() {
        var splitter = ProcessLineSplitter()
        #expect(splitter.append(Data("\n\r\n\n".utf8)).isEmpty)
        #expect(splitter.finish() == nil)
    }
}
