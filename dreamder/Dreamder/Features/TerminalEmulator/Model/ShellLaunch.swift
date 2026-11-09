import Foundation

nonisolated struct ProcessSpawn: Sendable, Equatable {
    let executable: String
    let arguments: [String]
    let environment: [String]
    let executableName: String
    let currentDirectory: String?
}

nonisolated enum ShellResolution: Sendable, Equatable {
    case ready(shell: Shell, path: String, replacedPath: String?)
    case unavailable(reason: String)
}

nonisolated enum LaunchPaths {
    static func isExecutableFile(atPath path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
            && FileManager.default.isExecutableFile(atPath: path)
    }

    static func isExistingDirectory(atPath path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
