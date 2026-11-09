import Foundation

nonisolated struct GitStatusPlan: Sendable, Equatable {
    private(set) var statuses: [String: GitStatus] = [:]
    private(set) var untrackedDirectories: Set<String> = []

    init() {}

    init(changedFiles: [GitChangedFile]) {
        for file in changedFiles {
            let key = file.ceFileKey
            let isDirectory = file.fileURL.hasDirectoryPath || key.hasSuffix("/")
            let path = key.withoutTrailingSlashes
            statuses[path] = file.anyStatus()
            if isDirectory, file.status == .untracked {
                untrackedDirectories.insert(path)
            }
        }
    }

    func status(forPath path: String) -> GitStatus? {
        if let status = statuses[path] {
            return status
        }
        guard !untrackedDirectories.isEmpty else { return nil }
        var ancestor = Substring(path)
        while let slash = ancestor.lastIndex(of: "/"), slash != ancestor.startIndex {
            ancestor = ancestor[..<slash]
            if untrackedDirectories.contains(String(ancestor)) {
                return .untracked
            }
        }
        return nil
    }
}
