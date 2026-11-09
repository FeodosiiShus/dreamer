import Foundation

nonisolated struct ConsoleFileLinkTarget: Sendable, Equatable {
    let url: URL
    let line: Int
    let column: Int
}

nonisolated struct ConsoleFileLinkResolver: Sendable {
    let baseDirectories: [URL]
    let fileExists: @Sendable (String) -> Bool

    init(
        baseDirectories: [URL],
        fileExists: @escaping @Sendable (String) -> Bool = { ConsoleFileLinkResolver.isRegularFile(atPath: $0) }
    ) {
        self.baseDirectories = baseDirectories
        self.fileExists = fileExists
    }

    func target(for link: ConsoleFileLink) -> ConsoleFileLinkTarget? {
        target(path: link.path, line: link.line, column: link.column)
    }

    func target(path: String, line: Int?, column: Int?) -> ConsoleFileLinkTarget? {
        for candidate in candidates(for: path) {
            if fileExists(candidate.path(percentEncoded: false)) {
                return ConsoleFileLinkTarget(url: candidate, line: max(line ?? 1, 1), column: max(column ?? 1, 1))
            }
        }
        return nil
    }

    static func isRegularFile(atPath path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && !isDirectory.boolValue
    }

    private func candidates(for path: String) -> [URL] {
        if path == "~" || path.hasPrefix("~/") {
            return [Self.standardized(URL(filePath: NSHomeDirectory() + String(path.dropFirst())))]
        }
        if path.hasPrefix("/") {
            return [Self.standardized(URL(filePath: path))]
        }
        return baseDirectories.map {
            Self.standardized($0.absoluteURL.appending(path: path, directoryHint: .notDirectory))
        }
    }

    private static func standardized(_ url: URL) -> URL {
        url.absoluteURL.standardizedFileURL
    }
}
