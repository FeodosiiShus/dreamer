import Foundation

final class LSPProcessEnvironment {
    static let shared = LSPProcessEnvironment()

    private struct Resolved {
        let loginPath: String?
        let npmGlobalBin: String?
        let searchPaths: [String]
    }

    private let lock = NSLock()
    private var cache: Resolved?

    var loginPath: String? {
        resolved.loginPath
    }

    var searchPaths: [String] {
        resolved.searchPaths
    }

    var environment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = resolved.searchPaths.joined(separator: ":")
        return environment
    }

    func xcrunFind(_ tool: String) -> String? {
        if let path = Self.runProcess("/usr/bin/xcrun", ["--find", tool]),
           FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        let fallback = Self.toolchainBinDirectory + "/" + tool
        return FileManager.default.isExecutableFile(atPath: fallback) ? fallback : nil
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

    private static let toolchainBinDirectory =
        "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin"

    private var resolved: Resolved {
        lock.lock()
        defer { lock.unlock() }
        if let cache {
            return cache
        }
        let loginPath = Self.loginShellPath()
        let npmGlobalBin = Self.npmGlobalBinPath()
        let searchPaths = Self.composedSearchPaths(
            loginPath: loginPath,
            homeDirectory: NSHomeDirectory(),
            npmGlobalBin: npmGlobalBin
        )
        let value = Resolved(loginPath: loginPath, npmGlobalBin: npmGlobalBin, searchPaths: searchPaths)
        cache = value
        return value
    }

    private static func loginShellPath() -> String? {
        let script = "printf '__DREAMDER_PATH__%s__DREAMDER_END__' \"$PATH\""
        if let output = runProcess("/bin/zsh", ["-l", "-i", "-c", script]),
           let path = extractMarkedPath(output) {
            return path
        }
        guard let path = runProcess("/bin/zsh", ["-l", "-c", "echo $PATH"]) else { return nil }
        return path.isEmpty ? nil : path
    }

    static func extractMarkedPath(_ output: String) -> String? {
        guard let start = output.range(of: "__DREAMDER_PATH__"),
              let end = output.range(of: "__DREAMDER_END__", range: start.upperBound..<output.endIndex) else {
            return nil
        }
        let path = String(output[start.upperBound..<end.lowerBound])
        return path.isEmpty ? nil : path
    }

    private static func npmGlobalBinPath() -> String? {
        guard let prefix = runProcess("/usr/bin/env", ["npm", "prefix", "-g"]) else { return nil }
        let bin = (prefix as NSString).appendingPathComponent("bin")
        return FileManager.default.fileExists(atPath: bin) ? bin : nil
    }

    private static func runProcess(_ executable: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe.closingOnExec()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let output, !output.isEmpty else { return nil }
        return output
    }
}
