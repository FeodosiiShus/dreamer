import Foundation

nonisolated struct WatchExclusionPolicy: Sendable {
    static let defaultRelativePaths = [
        ".git/objects",
        "node_modules",
        ".build",
        "build",
        "dist",
        "target",
        "DerivedData",
        ".gradle"
    ]
    static let streamPathLimit = 8
    static let nestedExcludedName = "node_modules"

    let rootPath: String
    let canonicalRootPath: String
    let streamRootPath: String
    private let cancelledDefaults: Set<String>
    private let relativeRoots: Set<String>
    private let orderedRelativeRoots: [String]

    init(folderURL: URL, rules: ExclusionRules) {
        rootPath = folderURL.path(percentEncoded: false).withoutTrailingSlashes
        canonicalRootPath = folderURL.resolvingSymlinksInPath().path(percentEncoded: false).withoutTrailingSlashes
        streamRootPath = Self.realPath(of: rootPath) ?? canonicalRootPath
        cancelledDefaults = rules.cancelledDefaults
        let activeDefaults = Self.defaultRelativePaths.filter { !rules.cancelledDefaults.contains($0) }
        var seen: Set<String> = []
        orderedRelativeRoots = (rules.excluded.sorted() + activeDefaults).filter { seen.insert($0).inserted }
        relativeRoots = Set(orderedRelativeRoots)
    }

    private static func realPath(of path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved).withoutTrailingSlashes
    }

    func streamExclusionPaths(
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> [String] {
        let absolute = orderedRelativeRoots.map { streamRootPath + "/" + $0 }
        let present = absolute.filter(fileExists)
        let absent = absolute.filter { !fileExists($0) }
        return Array((present + absent).prefix(Self.streamPathLimit))
    }

    func isDirectoryExcluded(_ directoryPath: String) -> Bool {
        guard directoryPath.hasPrefix(rootPath + "/") else { return false }
        var relative = ""
        for component in directoryPath.dropFirst(rootPath.count + 1).split(separator: "/") {
            relative = relative.isEmpty ? String(component) : "\(relative)/\(component)"
            if relativeRoots.contains(relative) { return true }
            if component == Self.nestedExcludedName, !cancelledDefaults.contains(relative) { return true }
        }
        return false
    }
}
