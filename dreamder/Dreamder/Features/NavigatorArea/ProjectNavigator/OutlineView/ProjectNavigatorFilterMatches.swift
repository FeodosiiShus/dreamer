import Foundation

nonisolated struct ProjectNavigatorTreeSource: Sendable {
    let rootURL: URL
    let fileSystem: any WorkspaceFileSystem
    let hiddenNames: Set<String>
    private let excludesFolder: @Sendable (URL) -> Bool

    init(
        rootURL: URL,
        fileSystem: any WorkspaceFileSystem,
        hiddenNames: Set<String>,
        scope: WorkspaceFileScope?
    ) {
        self.rootURL = rootURL
        self.fileSystem = fileSystem
        self.hiddenNames = hiddenNames
        excludesFolder = { scope?.isExcluded($0, isDirectory: true) ?? false }
    }

    func isExcludedFolder(_ url: URL) -> Bool {
        excludesFolder(url)
    }
}

nonisolated struct ProjectNavigatorFilterMatches: Sendable, Equatable {
    enum Candidates: Sendable {
        case tree(ProjectNavigatorTreeSource)
        case changedIDs([String])
    }

    static let inactive = ProjectNavigatorFilterMatches(text: "", sourceControl: false, ancestorIDs: [])

    let text: String
    let sourceControl: Bool
    let ancestorIDs: Set<String>

    var isBlank: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isActive: Bool {
        sourceControl || !isBlank
    }

    func matches(name: String) -> Bool {
        isBlank || name.localizedCaseInsensitiveContains(text)
    }

    @concurrent
    static func resolve(text: String, rootID: String, candidates: Candidates) async -> ProjectNavigatorFilterMatches {
        let base = rootID.withoutTrailingSlashes
        switch candidates {
        case .tree(let source):
            let probe = ProjectNavigatorFilterMatches(text: text, sourceControl: false, ancestorIDs: [])
            var ancestorIDs: Set<String> = []
            _ = probe.collectAncestors(in: source.rootURL, id: base, source: source, into: &ancestorIDs)
            return ProjectNavigatorFilterMatches(text: text, sourceControl: false, ancestorIDs: ancestorIDs)
        case .changedIDs(let ids):
            return changedMatches(text: text, base: base, ids: ids)
        }
    }

    private static func changedMatches(text: String, base: String, ids: [String]) -> ProjectNavigatorFilterMatches {
        let probe = ProjectNavigatorFilterMatches(text: text, sourceControl: true, ancestorIDs: [])
        var ancestorIDs: Set<String> = []
        for id in ids {
            let components = id.dropFirst(base.count + 1).split(separator: "/")
            guard let last = components.last, probe.matches(name: String(last)) else { continue }
            var ancestor = base
            for component in components.dropLast() {
                ancestor += "/\(component)"
                ancestorIDs.insert(ancestor)
            }
        }
        return ProjectNavigatorFilterMatches(text: text, sourceControl: true, ancestorIDs: ancestorIDs)
    }

    private func collectAncestors(
        in directory: URL,
        id: String,
        source: ProjectNavigatorTreeSource,
        into ancestorIDs: inout Set<String>
    ) -> Bool {
        var foundHit = false
        for entry in source.fileSystem.entries(in: directory) {
            if Task.isCancelled { return foundHit }
            guard !source.hiddenNames.contains(entry.name) else { continue }
            if matches(name: entry.name) {
                foundHit = true
                continue
            }
            guard entry.kind == .directory, !source.isExcludedFolder(entry.url) else { continue }
            let childID = "\(id)/\(entry.name)"
            if collectAncestors(in: entry.url, id: childID, source: source, into: &ancestorIDs) {
                ancestorIDs.insert(childID)
                foundHit = true
            }
        }
        return foundHit
    }
}
