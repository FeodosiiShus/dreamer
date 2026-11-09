import Foundation

nonisolated struct TaskEntry: Sendable {
    let name: String
    let command: String
    let manifestName: String?

    init(command: String) {
        self.name = command
        self.command = command
        self.manifestName = nil
    }

    init(name: String, command: String, manifestName: String) {
        self.name = name
        self.command = command
        self.manifestName = manifestName
    }
}

nonisolated struct ScannedDirectory: Sendable {
    let url: URL
    let relativePath: String
    let depth: Int
    let fileNames: Set<String>
    let subdirectoryNames: Set<String>

    func childPath(_ name: String) -> String {
        relativePath.isEmpty ? name : "\(relativePath)/\(name)"
    }

    func fileURL(_ name: String) -> URL {
        url.appending(path: name, directoryHint: .notDirectory)
    }

    func group(kind: TaskSourceKind, manifestName: String, entries: [TaskEntry]) -> DiscoveredTaskGroup? {
        guard !entries.isEmpty else { return nil }
        let manifest = childPath(manifestName)
        let suffix = relativePath.isEmpty ? "" : " (\(relativePath))"
        let tasks = entries.map {
            DiscoveredTask(
                kind: kind,
                name: $0.name + suffix,
                command: $0.command,
                workingDirectory: relativePath,
                manifest: $0.manifestName.map(childPath) ?? manifest
            )
        }
        return DiscoveredTaskGroup(kind: kind, directory: relativePath, manifest: manifest, tasks: tasks)
    }
}
