import Foundation

nonisolated struct TaskDiscovery: Sendable {
    static let defaultMaxDepth = 8
    static let defaultMaxVisitedDirectories = 20_000
    static let ignoredDirectoryNames: Set<String> = [
        "node_modules", "target", "build", "dist", "venv", "__pycache__", "Pods", "DerivedData", "vendor"
    ]

    private struct PendingDirectory {
        let url: URL
        let relativePath: String
        let depth: Int
    }

    private let rootURL: URL
    private let isExcluded: @Sendable (URL) -> Bool
    private let scanProbe: @Sendable () -> Void
    private let maxDepth: Int
    private let maxVisitedDirectories: Int

    init(
        rootURL: URL,
        isExcluded: @escaping @Sendable (URL) -> Bool = { _ in false },
        scanProbe: @escaping @Sendable () -> Void = {}
    ) {
        self.init(
            rootURL: rootURL,
            isExcluded: isExcluded,
            scanProbe: scanProbe,
            maxDepth: Self.defaultMaxDepth,
            maxVisitedDirectories: Self.defaultMaxVisitedDirectories
        )
    }

    init(
        rootURL: URL,
        isExcluded: @escaping @Sendable (URL) -> Bool,
        scanProbe: @escaping @Sendable () -> Void,
        maxDepth: Int,
        maxVisitedDirectories: Int
    ) {
        self.rootURL = rootURL
        self.isExcluded = isExcluded
        self.scanProbe = scanProbe
        self.maxDepth = maxDepth
        self.maxVisitedDirectories = maxVisitedDirectories
    }

    @concurrent func discover() async -> [DiscoveredTaskGroup] {
        scanProbe()
        var groups: [DiscoveredTaskGroup] = []
        var queue = [PendingDirectory(url: rootURL, relativePath: "", depth: 0)]
        var visited = 0
        while visited < queue.count && visited < maxVisitedDirectories {
            let pending = queue[visited]
            visited += 1
            guard let directory = scan(pending) else { continue }
            groups += Self.groups(in: directory)
            if pending.depth < maxDepth {
                queue += children(of: directory)
            }
        }
        return groups.sorted(by: Self.isOrderedBefore)
    }

    private func scan(_ pending: PendingDirectory) -> ScannedDirectory? {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: pending.url,
            includingPropertiesForKeys: keys
        ) else { return nil }
        var fileNames = Set<String>()
        var subdirectoryNames = Set<String>()
        for url in urls {
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true && values?.isSymbolicLink != true {
                subdirectoryNames.insert(url.lastPathComponent)
            } else {
                fileNames.insert(url.lastPathComponent)
            }
        }
        return ScannedDirectory(
            url: pending.url,
            relativePath: pending.relativePath,
            depth: pending.depth,
            fileNames: fileNames,
            subdirectoryNames: subdirectoryNames
        )
    }

    private func children(of directory: ScannedDirectory) -> [PendingDirectory] {
        directory.subdirectoryNames.sorted().compactMap { name in
            guard !name.hasPrefix("."), !Self.ignoredDirectoryNames.contains(name) else { return nil }
            let url = directory.url.appending(path: name, directoryHint: .isDirectory)
            guard !isExcluded(url) else { return nil }
            return PendingDirectory(url: url, relativePath: directory.childPath(name), depth: directory.depth + 1)
        }
    }

    private static func groups(in directory: ScannedDirectory) -> [DiscoveredTaskGroup] {
        [
            NpmTaskDiscovery.group(in: directory),
            CargoTaskDiscovery.group(in: directory),
            GoTaskDiscovery.group(in: directory),
            PythonTaskDiscovery.group(in: directory),
            SwiftPackageTaskDiscovery.group(in: directory),
            MakeTaskDiscovery.group(in: directory)
        ].compactMap { $0 }
    }

    private static func isOrderedBefore(_ lhs: DiscoveredTaskGroup, _ rhs: DiscoveredTaskGroup) -> Bool {
        let lhsDepth = depth(of: lhs.directory)
        let rhsDepth = depth(of: rhs.directory)
        if lhsDepth != rhsDepth {
            return lhsDepth < rhsDepth
        }
        if lhs.directory != rhs.directory {
            return lhs.directory < rhs.directory
        }
        return kindIndex(lhs.kind) < kindIndex(rhs.kind)
    }

    private static func depth(of directory: String) -> Int {
        directory.isEmpty ? 0 : directory.split(separator: "/").count
    }

    private static func kindIndex(_ kind: TaskSourceKind) -> Int {
        TaskSourceKind.allCases.prefix { $0 != kind }.count
    }
}
