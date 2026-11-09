import Foundation
@testable import Dreamder

enum TaskDiscoveryFixture {
    static func writeFile(_ relativePath: String, _ data: Data, in root: URL) throws {
        let url = root.appending(path: relativePath, directoryHint: .notDirectory)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    static func writeTree(_ files: [String: String], in root: URL) throws {
        for (path, content) in files {
            try writeFile(path, Data(content.utf8), in: root)
        }
    }

    static func discover(
        _ files: [String: String],
        isExcluded: @escaping @Sendable (URL) -> Bool = { _ in false }
    ) async throws -> [DiscoveredTaskGroup] {
        var groups: [DiscoveredTaskGroup] = []
        try await withTempDir { root in
            try writeTree(files, in: root)
            groups = await TaskDiscovery(rootURL: root, isExcluded: isExcluded).discover()
        }
        return groups
    }

    static func summary(_ groups: [DiscoveredTaskGroup]) -> [String] {
        groups.flatMap { group in
            group.tasks.map { "\(group.id) [\(group.manifest)] \($0.name) => \($0.command)" }
        }
    }

    static func lines(id: String, manifest: String, commands: [String], directory: String = "") -> [String] {
        let suffix = directory.isEmpty ? "" : " (\(directory))"
        return commands.map { "\(id) [\(manifest)] \($0)\(suffix) => \($0)" }
    }
}
