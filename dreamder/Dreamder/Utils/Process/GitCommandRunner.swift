import Foundation
import Synchronization

nonisolated enum GitCommandPolicy {
    static let querySubcommands: Set<String> = [
        "blame", "cat-file", "check-attr", "check-ignore", "cherry", "config", "count-objects", "describe",
        "diff", "diff-files", "diff-index", "diff-tree", "for-each-ref", "grep", "log", "ls-files", "ls-remote",
        "ls-tree", "merge-base", "name-rev", "reflog", "rev-list", "rev-parse", "shortlog", "show", "show-ref",
        "status", "symbolic-ref", "var", "version"
    ]

    static let readOnlySubcommands: Set<String> = querySubcommands.union([
        "branch", "clone", "fetch", "fsmonitor--daemon", "help", "merge-tree", "notes", "push", "remote", "tag",
        "worktree"
    ])

    static let optionsConsumingNextArgument: Set<String> = ["-c", "-C", "--git-dir", "--work-tree", "--namespace"]

    static func subcommand(in arguments: [String]) -> (name: String, arguments: ArraySlice<String>)? {
        var index = arguments.startIndex
        while index < arguments.endIndex {
            let argument = arguments[index]
            if optionsConsumingNextArgument.contains(argument) {
                index += 2
            } else if argument.hasPrefix("-") {
                index += 1
            } else {
                return (argument, arguments[(index + 1)...])
            }
        }
        return nil
    }

    static func isReadOnly(_ arguments: [String]) -> Bool {
        guard let command = subcommand(in: arguments) else { return true }
        return isStashQuery(command) || readOnlySubcommands.contains(command.name)
    }

    static func isQuery(_ arguments: [String]) -> Bool {
        guard let command = subcommand(in: arguments) else { return true }
        return isStashQuery(command) || querySubcommands.contains(command.name)
    }

    private static func isStashQuery(_ command: (name: String, arguments: ArraySlice<String>)) -> Bool {
        command.name == "stash" && (command.arguments.first == "list" || command.arguments.first == "show")
    }
}

actor GitWriteGate {
    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if !isLocked {
            isLocked = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if waiters.isEmpty {
            isLocked = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}

nonisolated enum GitRepositoryGates {
    private static let gates = Mutex<[String: GitWriteGate]>([:])

    static func gate(for directory: URL?) -> GitWriteGate {
        let key = directory?.resolvingSymlinksInPath().standardizedFileURL.path(percentEncoded: false) ?? ""
        return gates.withLock { gates in
            if let gate = gates[key] {
                return gate
            }
            let gate = GitWriteGate()
            gates[key] = gate
            return gate
        }
    }
}

actor GitExecutableLocator {
    nonisolated static let shared = GitExecutableLocator()

    private let runner: any ProcessRunning
    private let fallback: URL
    private var lookup: Task<URL, Never>?

    init(
        runner: any ProcessRunning = ProcessRunner(),
        fallback: URL = URL(fileURLWithPath: "/usr/bin/git")
    ) {
        self.runner = runner
        self.fallback = fallback
    }

    func executableURL() async -> URL {
        if let lookup {
            return await lookup.value
        }
        let task = Task { [runner, fallback] in
            await Self.resolve(runner: runner, fallback: fallback)
        }
        lookup = task
        return await task.value
    }

    private static func resolve(runner: any ProcessRunning, fallback: URL) async -> URL {
        let invocation = ProcessInvocation(
            executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
            arguments: ["--find", "git"],
            timeout: .seconds(10)
        )
        guard let output = try? await runner.run(invocation), output.succeeded else { return fallback }
        let path = output.standardOutputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) else { return fallback }
        return URL(fileURLWithPath: path)
    }
}

nonisolated struct GitCommandRunner: Sendable {
    typealias EnvironmentProvider = @Sendable () async -> [String: String]

    static let configuration = ["-c", "core.quotepath=false", "-c", "log.showSignature=false"]

    private let runner: any ProcessRunning
    private let gitExecutable: URL?
    private let baseEnvironment: EnvironmentProvider?

    init(
        runner: any ProcessRunning = ProcessRunner(),
        gitExecutable: URL? = nil,
        baseEnvironment: EnvironmentProvider? = nil
    ) {
        self.runner = runner
        self.gitExecutable = gitExecutable
        self.baseEnvironment = baseEnvironment
    }

    @concurrent
    func run(
        arguments: [String],
        workingDirectory: URL?,
        standardInput: Data? = nil,
        timeout: Duration? = nil
    ) async throws -> GitCommandResult {
        let readOnly = GitCommandPolicy.isReadOnly(arguments)
        let invocation = await makeInvocation(
            arguments: arguments,
            workingDirectory: workingDirectory,
            readOnly: readOnly,
            standardInput: standardInput,
            timeout: timeout
        )
        if readOnly {
            return try await execute(invocation)
        }
        let gate = GitRepositoryGates.gate(for: workingDirectory)
        await gate.acquire()
        do {
            try Task.checkCancellation()
            let result = try await execute(invocation)
            await gate.release()
            return result
        } catch {
            await gate.release()
            throw error
        }
    }

    func stream(arguments: [String], workingDirectory: URL?) -> AsyncThrowingStream<ProcessEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let invocation = await makeInvocation(
                        arguments: arguments,
                        workingDirectory: workingDirectory,
                        readOnly: GitCommandPolicy.isReadOnly(arguments),
                        standardInput: nil,
                        timeout: nil
                    )
                    for try await event in runner.stream(invocation) {
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func execute(_ invocation: ProcessInvocation) async throws -> GitCommandResult {
        do {
            return GitCommandResult(try await runner.run(invocation))
        } catch ProcessRunnerError.launchFailed(let executable, let reason) {
            return .startFailed("Failed to start \(executable): \(reason)")
        }
    }

    private func makeInvocation(
        arguments: [String],
        workingDirectory: URL?,
        readOnly: Bool,
        standardInput: Data?,
        timeout: Duration?
    ) async -> ProcessInvocation {
        let executable: URL
        if let gitExecutable {
            executable = gitExecutable
        } else {
            executable = await GitExecutableLocator.shared.executableURL()
        }
        let source: [String: String]
        if let baseEnvironment {
            source = await baseEnvironment()
        } else {
            source = await ShellEnvironment.shared.load()
        }
        return ProcessInvocation(
            executable: executable,
            arguments: Self.configuration + arguments,
            workingDirectory: workingDirectory,
            environment: Self.environment(from: source, readOnly: readOnly),
            standardInput: standardInput,
            timeout: timeout
        )
    }

    static func environment(from source: [String: String], readOnly: Bool) -> [String: String] {
        var environment = ProcessEnvironment.sanitized(source)
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["LC_MESSAGES"] = "C"
        environment.removeValue(forKey: "LC_ALL")
        environment.removeValue(forKey: "LANGUAGE")
        if readOnly {
            environment["GIT_OPTIONAL_LOCKS"] = "0"
        }
        return environment
    }
}
