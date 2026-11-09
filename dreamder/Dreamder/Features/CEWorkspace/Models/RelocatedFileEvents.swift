import Foundation

nonisolated struct RelocatedFileEvents: Sendable {
    let events: [DirectoryEventStream.Event]
    let treeParents: Set<String>
    let rescanRoots: Set<String>
    let modifiedFiles: Set<String>

    init(_ rawEvents: [DirectoryEventStream.Event], folderPath: String, policy: WatchExclusionPolicy) {
        var canonicalParents: [String: String] = [:]
        var excludedDirectories: [String: Bool] = [:]
        var kept: [DirectoryEventStream.Event] = []
        var parents: Set<String> = []
        var rescans: Set<String> = []
        var modified: Set<String> = []
        kept.reserveCapacity(rawEvents.count)

        for event in rawEvents {
            let path = Self.relocate(
                event.path,
                folderPath: folderPath,
                canonicalRoot: policy.canonicalRootPath,
                canonicalParents: &canonicalParents
            )
            let parent = Self.parentPath(of: path)
            let isExcluded: Bool
            if let cached = excludedDirectories[parent] {
                isExcluded = cached
            } else {
                isExcluded = policy.isDirectoryExcluded(parent)
                excludedDirectories[parent] = isExcluded
            }
            if isExcluded { continue }
            kept.append(DirectoryEventStream.Event(path: path, eventType: event.eventType))
            if Self.changesTree(event.eventType) {
                parents.insert(parent)
            }
            if event.eventType == .mustRescan {
                rescans.insert(path)
            }
            if event.eventType == .itemModified, !path.contains("/.git/") {
                modified.insert(path)
            }
        }
        events = kept
        treeParents = parents
        rescanRoots = rescans
        modifiedFiles = modified.filter { path in
            (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
        }
    }

    private static func changesTree(_ eventType: FSEvent) -> Bool {
        switch eventType {
        case .itemCreated, .itemCloned, .itemRemoved, .itemRenamed:
            true
        case .changeInDirectory, .itemChangedOwner, .itemModified, .mustRescan:
            false
        }
    }

    private static func parentPath(of path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return path }
        return slash == path.startIndex ? "/" : String(path[..<slash])
    }

    private static func relocate(
        _ path: String,
        folderPath: String,
        canonicalRoot: String,
        canonicalParents: inout [String: String]
    ) -> String {
        if path == canonicalRoot {
            return folderPath
        }
        guard let slash = path.lastIndex(of: "/") else { return path }
        let parent = parentPath(of: path)
        let canonicalParent: String
        if let cached = canonicalParents[parent] {
            canonicalParent = cached
        } else {
            canonicalParent = URL(fileURLWithPath: parent).resolvingSymlinksInPath()
                .path(percentEncoded: false).withoutTrailingSlashes
            canonicalParents[parent] = canonicalParent
        }
        guard canonicalParent == canonicalRoot || canonicalParent.hasPrefix(canonicalRoot + "/") else {
            return path
        }
        let name = path[path.index(after: slash)...]
        return "\(folderPath)\(canonicalParent.dropFirst(canonicalRoot.count))/\(name)"
    }
}
