import Foundation

nonisolated enum RegistryInputValidation {
    static let packageManagerExecutables: Set<String> = [
        "npm", "cargo", "go", "git", "python", "python3", "pip3", "tar", "gunzip"
    ]

    static let buildExecutables: Set<String> = [
        "make", "cmake", "cargo", "npm", "yarn", "pnpm", "go", "dotnet", "swift", "zig"
    ]

    private static let alphanumerics = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
    private static let componentCharacters = alphanumerics.union("._+-~@")
    private static let argumentCharacters = componentCharacters.union("/^,")
    private static let buildArgumentCharacters = argumentCharacters.union("=:")
    private static let urlCharacters = argumentCharacters.union(":")
    private static let httpsPrefix = "https://"

    static func isAllowedExecutable(_ executable: String) -> Bool {
        packageManagerExecutables.contains(executable)
            || buildExecutables.contains(executable)
            || executable.hasPrefix("/")
    }

    static func component(_ value: String) throws -> String {
        guard !value.isEmpty, !value.hasPrefix("-"), value.allSatisfy(componentCharacters.contains) else {
            throw PackageManagerError.unsafeValue(value)
        }
        return value
    }

    static func child(of root: URL, named name: String) throws -> URL {
        let child = root.appending(path: try component(name))
        let rootPath = root.standardizedFileURL.path
        let childPath = child.standardizedFileURL.path
        guard childPath.hasPrefix(rootPath + "/") else {
            throw PackageManagerError.unsafeValue(name)
        }
        return child
    }

    static func argument(_ value: String) throws -> String {
        guard !value.isEmpty,
              !value.hasPrefix("-"),
              !value.hasPrefix("/"),
              !value.split(separator: "/", omittingEmptySubsequences: false).contains(".."),
              value.allSatisfy(argumentCharacters.contains) else {
            throw PackageManagerError.unsafeValue(value)
        }
        return value
    }

    static func httpsURL(_ value: String) throws -> String {
        guard value.hasPrefix(httpsPrefix),
              value.allSatisfy(urlCharacters.contains),
              URL(string: value)?.host(percentEncoded: false)?.isEmpty == false else {
            throw PackageManagerError.unsafeValue(value)
        }
        return value
    }

    static func buildCommand(_ command: String) throws -> [[String]] {
        var lines: [[String]] = []
        for line in command.split(whereSeparator: \.isNewline) {
            let tokens = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard let executable = tokens.first else { continue }
            let arguments = tokens.dropFirst()
            guard buildExecutables.contains(executable),
                  arguments.allSatisfy({ $0.allSatisfy(buildArgumentCharacters.contains) }) else {
                throw PackageManagerError.unsafeValue(String(line))
            }
            lines.append(tokens)
        }
        guard !lines.isEmpty else {
            throw PackageManagerError.unsafeValue(command)
        }
        return lines
    }
}
