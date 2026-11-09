import Foundation

nonisolated struct RecentProject: Codable, Hashable, Identifiable, Sendable {
    var path: String
    var displayName: String
    var projectOpenTimestamp: Int64
    var isDirectory: Bool
    var hidden: Bool

    var id: String { path }

    var url: URL {
        URL(filePath: path, directoryHint: isDirectory ? .isDirectory : .notDirectory)
    }

    var abbreviatedPath: String {
        (path as NSString).abbreviatingWithTildeInPath
    }

    static func displayName(forPath path: String) -> String {
        (path as NSString).lastPathComponent
    }
}
