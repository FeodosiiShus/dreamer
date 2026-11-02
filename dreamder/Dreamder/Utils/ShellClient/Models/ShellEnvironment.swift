import Foundation

final class ShellEnvironment {
    static let shared = ShellEnvironment()

    private static let loadTimeout: TimeInterval = 10
    private static let waitTimeout: TimeInterval = 5

    private let condition = NSCondition()
    private var cached: [String: String]?
    private var isLoading = false

    var environment: [String: String] {
        condition.lock()
        if let cached {
            condition.unlock()
            return cached
        }
        if Thread.isMainThread {
            condition.unlock()
            prepare()
            return Self.fallbackEnvironment
        }
        if isLoading {
            let deadline = Date(timeIntervalSinceNow: Self.waitTimeout)
            while cached == nil && isLoading {
                if !condition.wait(until: deadline) {
                    break
                }
            }
            let value = cached ?? Self.fallbackEnvironment
            condition.unlock()
            return value
        }
        isLoading = true
        condition.unlock()
        return finishLoading()
    }

    func prepare() {
        condition.lock()
        guard cached == nil, !isLoading else {
            condition.unlock()
            return
        }
        isLoading = true
        condition.unlock()
        DispatchQueue.global(qos: .utility).async {
            _ = self.finishLoading()
        }
    }

    @discardableResult
    private func finishLoading() -> [String: String] {
        let value = Self.loadLoginEnvironment() ?? Self.fallbackEnvironment
        condition.lock()
        cached = value
        isLoading = false
        condition.broadcast()
        condition.unlock()
        return value
    }

    private static func loadLoginEnvironment() -> [String: String]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lic", "env -0"]
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let pipe = Pipe.closingOnExec()
        process.standardOutput = pipe
        do {
            try process.run()
        } catch {
            return nil
        }
        let watchdog = DispatchWorkItem {
            if process.isRunning {
                process.terminate()
            }
        }
        DispatchQueue.global(qos: .utility)
            .asyncAfter(deadline: .now() + loadTimeout, execute: watchdog)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        watchdog.cancel()
        process.waitUntilExit()
        return parse(data)
    }

    private static func parse(_ data: Data) -> [String: String]? {
        var environment = ProcessInfo.processInfo.environment
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

    private static var fallbackEnvironment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let existing = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let additions = fallbackDirectories.filter { !existing.contains($0) }
        environment["PATH"] = (existing + additions).joined(separator: ":")
        return environment
    }

    private static let fallbackDirectories = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        NSHomeDirectory() + "/.local/bin",
        NSHomeDirectory() + "/.bun/bin",
        NSHomeDirectory() + "/.local/share/mise/shims"
    ]
}
