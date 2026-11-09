import Foundation

nonisolated enum NpmTaskDiscovery {
    private static let manifestName = "package.json"
    private static let defaultPackageManager = "npm"
    private static let lockfiles: [(file: String, packageManager: String)] = [
        ("pnpm-lock.yaml", "pnpm"),
        ("yarn.lock", "yarn"),
        ("bun.lockb", "bun"),
        ("bun.lock", "bun")
    ]

    static func group(in directory: ScannedDirectory) -> DiscoveredTaskGroup? {
        guard directory.fileNames.contains(manifestName),
              let data = try? Data(contentsOf: directory.fileURL(manifestName)),
              let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let scripts = manifest["scripts"] as? [String: Any] else { return nil }
        let packageManager = packageManager(for: directory)
        let entries = scripts
            .compactMap { $0.value is String ? $0.key : nil }
            .sorted()
            .map { TaskEntry(command: "\(packageManager) run \($0)") }
        return directory.group(kind: .npm, manifestName: manifestName, entries: entries)
    }

    private static func packageManager(for directory: ScannedDirectory) -> String {
        var current = directory.url
        for _ in 0...directory.depth {
            for lockfile in lockfiles {
                let path = current.appending(path: lockfile.file, directoryHint: .notDirectory).path(percentEncoded: false)
                if FileManager.default.fileExists(atPath: path) {
                    return lockfile.packageManager
                }
            }
            current = current.deletingLastPathComponent()
        }
        return defaultPackageManager
    }
}
