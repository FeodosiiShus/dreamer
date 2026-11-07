import Foundation
import Synchronization

nonisolated final class LSPProcessEnvironment: Sendable {
    nonisolated static let shared = LSPProcessEnvironment()

    struct Resolved: Sendable, Equatable {
        let loginPath: String?
        let npmGlobalBin: String?
        let searchPaths: [String]
        let environment: [String: String]
    }

    private struct XcrunResult: Sendable {
        let path: String?
    }

    private struct State {
        var resolved: Resolved?
        var loading: Task<Resolved, Never>?
        var xcrunResults: [String: XcrunResult] = [:]
    }

    private static let probeTimeout: Duration = .seconds(10)

    private let shellEnvironment: ShellEnvironment
    private let runner: any ProcessRunning
    private let homeDirectory: String
    private let state = Mutex(State())

    init(
        shellEnvironment: ShellEnvironment = .shared,
        runner: any ProcessRunning = ProcessRunner(),
        homeDirectory: String = NSHomeDirectory()
    ) {
        self.shellEnvironment = shellEnvironment
        self.runner = runner
        self.homeDirectory = homeDirectory
    }

    var loginPath: String? {
        current.loginPath
    }

    var searchPaths: [String] {
        current.searchPaths
    }

    var environment: [String: String] {
        current.environment
    }

    func resolve() async -> Resolved {
        enum Step {
            case resolved(Resolved)
            case loading(Task<Resolved, Never>)
        }
        let step = state.withLock { state -> Step in
            if let resolved = state.resolved {
                return .resolved(resolved)
            }
            if let loading = state.loading {
                return .loading(loading)
            }
            let task = Task { await self.load() }
            state.loading = task
            return .loading(task)
        }
        switch step {
        case .resolved(let resolved):
            return resolved
        case .loading(let task):
            return await task.value
        }
    }

    func xcrunFind(_ tool: String) async -> String? {
        if let cached = state.withLock({ $0.xcrunResults[tool] }) {
            return cached.path
        }
        let environment = ProcessInfo.processInfo.environment
        var path: String?
        if let found = await standardOutput(of: "/usr/bin/xcrun", ["--find", tool], environment: environment),
           FileManager.default.isExecutableFile(atPath: found) {
            path = found
        } else {
            let fallback = Self.toolchainBinDirectory + "/" + tool
            path = FileManager.default.isExecutableFile(atPath: fallback) ? fallback : nil
        }
        state.withLock { $0.xcrunResults[tool] = XcrunResult(path: path) }
        return path
    }

    func findExecutable(named name: String) -> String? {
        for directory in searchPaths {
            let path = (directory as NSString).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    static func composedSearchPaths(
        loginPath: String?,
        homeDirectory: String,
        npmGlobalBin: String? = nil,
        extraDirectories: [String] = []
    ) -> [String] {
        var directories = loginPath?
            .split(separator: ":")
            .map { String($0).trimmingCharacters(in: .whitespaces) } ?? []
        directories.append(contentsOf: [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(homeDirectory)/.local/bin",
            "\(homeDirectory)/.cargo/bin",
            "\(homeDirectory)/go/bin",
            "\(homeDirectory)/.bun/bin"
        ])
        if let npmGlobalBin {
            directories.append(npmGlobalBin)
        }
        directories.append(contentsOf: extraDirectories)
        directories.append(toolchainBinDirectory)

        var seen = Set<String>()
        return directories.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    static func extractMarkedPath(_ output: String) -> String? {
        guard let start = output.range(of: "__DREAMDER_PATH__"),
              let end = output.range(of: "__DREAMDER_END__", range: start.upperBound..<output.endIndex) else {
            return nil
        }
        let path = String(output[start.upperBound..<end.lowerBound])
        return path.isEmpty ? nil : path
    }

    private static let toolchainBinDirectory =
        "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin"

    private var current: Resolved {
        if let resolved = state.withLock({ $0.resolved }) {
            return resolved
        }
        let shell = shellEnvironment.environment
        let loginPath = shell["PATH"]
        let searchPaths = Self.composedSearchPaths(loginPath: loginPath, homeDirectory: homeDirectory)
        return Resolved(
            loginPath: loginPath,
            npmGlobalBin: nil,
            searchPaths: searchPaths,
            environment: Self.replacingPath(in: shell, with: searchPaths)
        )
    }

    private func load() async -> Resolved {
        let resolution = await shellEnvironment.resolve()
        var loginPath = resolution.environment["PATH"]
        if !resolution.isLoginEnvironment, let probed = await probeLoginPath(environment: resolution.environment) {
            loginPath = probed
        }
        var toolEnvironment = resolution.environment
        toolEnvironment["PATH"] = loginPath ?? toolEnvironment["PATH"]
        let npmGlobalBin = await npmGlobalBinPath(environment: toolEnvironment)
        let searchPaths = Self.composedSearchPaths(
            loginPath: loginPath,
            homeDirectory: homeDirectory,
            npmGlobalBin: npmGlobalBin
        )
        let resolved = Resolved(
            loginPath: loginPath,
            npmGlobalBin: npmGlobalBin,
            searchPaths: searchPaths,
            environment: Self.replacingPath(in: resolution.environment, with: searchPaths)
        )
        state.withLock { state in
            state.resolved = resolved
            state.loading = nil
        }
        return resolved
    }

    private func probeLoginPath(environment: [String: String]) async -> String? {
        let script = "printf '__DREAMDER_PATH__%s__DREAMDER_END__' \"$PATH\""
        guard let output = await standardOutput(of: "/bin/zsh", ["-l", "-c", script], environment: environment) else {
            return nil
        }
        return Self.extractMarkedPath(output)
    }

    private func npmGlobalBinPath(environment: [String: String]) async -> String? {
        guard let prefix = await standardOutput(of: "/usr/bin/env", ["npm", "prefix", "-g"], environment: environment)
        else {
            return nil
        }
        let bin = (prefix as NSString).appendingPathComponent("bin")
        return FileManager.default.fileExists(atPath: bin) ? bin : nil
    }

    private func standardOutput(
        of executable: String,
        _ arguments: [String],
        environment: [String: String]
    ) async -> String? {
        let invocation = ProcessInvocation(
            executable: URL(fileURLWithPath: executable),
            arguments: arguments,
            environment: environment,
            timeout: Self.probeTimeout
        )
        guard let output = try? await runner.run(invocation), output.succeeded else { return nil }
        let text = output.standardOutputText.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func replacingPath(in base: [String: String], with searchPaths: [String]) -> [String: String] {
        var environment = base
        environment["PATH"] = searchPaths.joined(separator: ":")
        return environment
    }
}
