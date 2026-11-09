import Foundation

nonisolated struct FileManagerDiagnostics: Sendable {
    var directoryListed: @Sendable (_ directoryID: String, _ onMainThread: Bool) -> Void
    var directoryRebuilt: @Sendable (_ directoryID: String) -> Void

    static let silent = FileManagerDiagnostics(
        directoryListed: { _, _ in },
        directoryRebuilt: { _ in }
    )
}

nonisolated struct DirectoryListing: Sendable {
    nonisolated struct Entry: Sendable, Equatable {
        let id: String
        let url: URL
        let isDirectory: Bool
    }

    nonisolated struct NaturalKey: Sendable {
        let name: String
        let parts: [String]

        init(_ name: String) {
            self.name = name
            parts = name.components(separatedBy: CharacterSet.decimalDigits.inverted)
        }

        func precedes(_ other: NaturalKey) -> Bool {
            for (lhsPart, rhsPart) in zip(parts, other.parts) where lhsPart != rhsPart {
                if let lhsNumber = Int(lhsPart), let rhsNumber = Int(rhsPart) {
                    return lhsNumber < rhsNumber
                }
                return lhsPart < rhsPart
            }
            return name < other.name
        }
    }

    private nonisolated struct SortableEntry {
        let entry: Entry
        let key: NaturalKey
    }

    let directoryID: String
    let entries: [Entry]

    static func childURL(of directoryID: String, named name: String) -> URL {
        URL(filePath: directoryID).appending(path: name)
    }

    static func read(
        directoryID: String,
        at directoryURL: URL,
        ignoring ignoredNames: Set<String>,
        diagnostics: FileManagerDiagnostics = .silent
    ) throws -> DirectoryListing {
        diagnostics.directoryListed(directoryID, Thread.isMainThread)
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        let contents = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: keys,
            options: []
        )
        let parentURL = URL(filePath: directoryID)
        var sortable: [SortableEntry] = []
        sortable.reserveCapacity(contents.count)
        for item in contents {
            let name = item.lastPathComponent
            if ignoredNames.contains(name) { continue }
            let url = parentURL.appending(path: name)
            sortable.append(
                SortableEntry(
                    entry: Entry(id: url.relativePath, url: url, isDirectory: isDirectory(item)),
                    key: NaturalKey(name)
                )
            )
        }
        sortable.sort { lhs, rhs in
            if lhs.entry.isDirectory != rhs.entry.isDirectory {
                return lhs.entry.isDirectory
            }
            return lhs.key.precedes(rhs.key)
        }
        return DirectoryListing(directoryID: directoryID, entries: sortable.map(\.entry))
    }

    private static func isDirectory(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        if values?.isSymbolicLink == true {
            let resolved = try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey])
            return resolved?.isDirectory == true
        }
        return values?.isDirectory == true
    }
}

nonisolated extension String {
    var withoutTrailingSlashes: String {
        var trimmed = self
        while trimmed.count > 1, trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        return trimmed
    }
}
