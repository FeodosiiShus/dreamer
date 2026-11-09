import Foundation
import Synchronization

nonisolated final class ShellEnvironment: Sendable {
    nonisolated static let shared = ShellEnvironment()

    struct Resolution: Sendable, Equatable {
        var environment: [String: String]
        var isLoginEnvironment: Bool
    }

    private enum Step {
        case resolved(Resolution)
        case loading(Task<Resolution, Never>)
    }

    private enum Cached {
        case login(Resolution)
        case fallback(Resolution, since: ContinuousClock.Instant)
    }

    private struct State {
        var cached: Cached?
        var loading: Task<Resolution, Never>?
    }

    private let runner: any ProcessRunning
    private let loadTimeout: Duration
    private let retryInterval: Duration
    private let now: @Sendable () -> ContinuousClock.Instant
    private let baseEnvironment: @Sendable () -> [String: String]
    private let shellExecutable: URL
    private let shellArguments: [String]
    private let state = Mutex(State())

    init(
        runner: any ProcessRunning = ProcessRunner(),
        loadTimeout: Duration = .seconds(10),
        retryInterval: Duration = .seconds(30),
        now: @escaping @Sendable () -> ContinuousClock.Instant = { ContinuousClock.now },
        baseEnvironment: @escaping @Sendable () -> [String: String] = { ProcessInfo.processInfo.environment },
        shellExecutable: URL = URL(fileURLWithPath: "/bin/zsh"),
        shellArguments: [String] = ["-lic", "env -0"]
    ) {
        self.runner = runner
        self.loadTimeout = loadTimeout
        self.retryInterval = retryInterval
        self.now = now
        self.baseEnvironment = baseEnvironment
        self.shellExecutable = shellExecutable
        self.shellArguments = shellArguments
    }

    var cachedEnvironment: [String: String]? {
        state.withLock { state in
            guard case .login(let resolution) = state.cached else { return nil }
            return resolution.environment
        }
    }

    var environment: [String: String] {
        if let cachedEnvironment {
            return cachedEnvironment
        }
        prepare()
        return Self.fallbackEnvironment(base: baseEnvironment())
    }

    func prepare() {
        _ = loadingTask()
    }

    func load() async -> [String: String] {
        await resolve().environment
    }

    func resolve() async -> Resolution {
        switch loadingTask() {
        case .resolved(let resolution):
            return resolution
        case .loading(let task):
            return await task.value
        }
    }

    private func loadingTask() -> Step {
        state.withLock { state in
            switch state.cached {
            case .login(let resolution):
                return .resolved(resolution)
            case let .fallback(resolution, since):
                if state.loading == nil, isRetryDue(since: since) {
                    state.loading = Task { await self.performLoad() }
                }
                return .resolved(resolution)
            case nil:
                if let loading = state.loading {
                    return .loading(loading)
                }
                let task = Task { await self.performLoad() }
                state.loading = task
                return .loading(task)
            }
        }
    }

    private func isRetryDue(since fallbackSince: ContinuousClock.Instant) -> Bool {
        now() - fallbackSince >= retryInterval
    }

    private func performLoad() async -> Resolution {
        let startedAt = now()
        let resolution: Resolution
        let cached: Cached
        if let login = await loadLoginEnvironment() {
            resolution = login
            cached = .login(login)
        } else {
            resolution = Resolution(
                environment: Self.fallbackEnvironment(base: baseEnvironment()),
                isLoginEnvironment: false
            )
            cached = .fallback(resolution, since: startedAt)
        }
        state.withLock { state in
            state.cached = cached
            state.loading = nil
        }
        return resolution
    }

    private func loadLoginEnvironment() async -> Resolution? {
        let base = baseEnvironment()
        let invocation = ProcessInvocation(
            executable: shellExecutable,
            arguments: shellArguments,
            environment: ProcessEnvironment.sanitized(base),
            timeout: loadTimeout
        )
        guard let output = try? await runner.run(invocation),
              let environment = Self.parse(output.standardOutput, base: base) else {
            return nil
        }
        return Resolution(environment: environment, isLoginEnvironment: true)
    }

    static func parse(_ data: Data, base: [String: String]) -> [String: String]? {
        var environment = base
        var parsedEntries = 0
        for entry in data.split(separator: 0) {
            guard let string = String(bytes: entry, encoding: .utf8),
                  let separatorIndex = string.firstIndex(of: "=") else {
                continue
            }
            let name = String(string[string.startIndex..<separatorIndex])
            guard isValidVariableName(name) else {
                continue
            }
            environment[name] = String(string[string.index(after: separatorIndex)...])
            parsedEntries += 1
        }
        guard parsedEntries > 0, let path = environment["PATH"], !path.isEmpty else {
            return nil
        }
        for name in sessionVariables {
            environment.removeValue(forKey: name)
        }
        return ProcessEnvironment.sanitized(environment)
    }

    static func fallbackEnvironment(base: [String: String]) -> [String: String] {
        var environment = ProcessEnvironment.sanitized(base)
        let existing = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let additions = fallbackDirectories.filter { !existing.contains($0) }
        environment["PATH"] = (existing + additions).joined(separator: ":")
        return environment
    }

    private static func isValidVariableName(_ name: String) -> Bool {
        guard let first = name.first, first.isLetter || first == "_" else {
            return false
        }
        return name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    private static let sessionVariables = [
        "_", "SHLVL", "PWD", "OLDPWD", "ZDOTDIR", "ZSH_EXECUTION_STRING", "ZSH_SUBSHELL", "ZSH_ARGZERO"
    ]

    private static let fallbackDirectories = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        NSHomeDirectory() + "/.local/bin",
        NSHomeDirectory() + "/.bun/bin",
        NSHomeDirectory() + "/.local/share/mise/shims"
    ]
}
