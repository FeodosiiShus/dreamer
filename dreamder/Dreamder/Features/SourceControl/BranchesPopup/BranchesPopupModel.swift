import Foundation

nonisolated struct GitTag: Hashable, Identifiable {
    let name: String
    let objectName: String

    var id: String { name }

    static func list(from output: String) -> [GitTag] {
        output
            .components(separatedBy: .newlines)
            .compactMap { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return nil }
                let parts = trimmed.components(separatedBy: "|")
                guard let name = parts.first, !name.isEmpty else { return nil }
                return GitTag(name: name, objectName: parts.count > 1 ? parts[1] : "")
            }
            .sorted { $0.name < $1.name }
    }
}

nonisolated struct BranchesPopupRef: Hashable, Identifiable {
    nonisolated enum Kind: Hashable {
        case local
        case remote
        case tag
    }

    let kind: Kind
    let name: String
    let shortName: String
    let upstream: String?
    let isCurrent: Bool
    var ahead: Int = 0
    var behind: Int = 0

    var id: String {
        switch kind {
        case .local: "local:\(shortName)"
        case .remote: "remote:\(shortName)"
        case .tag: "tag:\(shortName)"
        }
    }

    var displayName: String {
        kind == .local ? name : shortName
    }

    func itemID(in section: BranchesPopupSectionID) -> BranchesPopupItemID {
        .ref(section, shortName)
    }

    var iconName: String {
        switch kind {
        case .local: isCurrent ? "vcs/currentBranchLabel" : "general/vcs"
        case .remote: "general/vcs"
        case .tag: "vcs/branchLabel"
        }
    }

    var remoteAndBranch: (remote: String, branch: String)? {
        guard kind == .remote else { return nil }
        let parts = shortName.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        return (parts[0], parts[1])
    }

    var counterText: String? {
        guard kind == .local, ahead > 0 || behind > 0 else { return nil }
        var parts: [String] = []
        if ahead > 0 { parts.append("↑\(ahead)") }
        if behind > 0 { parts.append("↓\(behind)") }
        return parts.joined(separator: " ")
    }
}

nonisolated enum BranchesPopupActionID: String, CaseIterable, Hashable, Identifiable {
    case updateProject
    case commit
    case push
    case newBranch
    case newWorktree
    case checkoutRevision

    var id: String { rawValue }

    var title: String {
        switch self {
        case .updateProject: "Update Project"
        case .commit: "Commit…"
        case .push: "Push…"
        case .newBranch: "New Branch…"
        case .newWorktree: "New Worktree…"
        case .checkoutRevision: "Checkout Tag or Revision…"
        }
    }

    var iconName: String {
        switch self {
        case .updateProject: "vcs/update"
        case .commit: "vcs/commit"
        case .push: "vcs/push"
        case .newBranch: "general/add"
        case .newWorktree: "vcs/branch"
        case .checkoutRevision: "vcs/branch"
        }
    }

    var shortcut: String? {
        switch self {
        case .updateProject: "⌘T"
        case .commit: "⌘K"
        case .push: "⇧⌘K"
        case .newBranch: "⌥⌘N"
        case .newWorktree: nil
        case .checkoutRevision: nil
        }
    }
}

nonisolated enum BranchesPopupOngoingAction: String, CaseIterable, Hashable, Identifiable {
    case rebaseAbort
    case mergeAbort
    case cherryPickAbort
    case cherryPickContinue
    case revertAbort
    case rebaseContinue
    case rebaseSkip

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rebaseAbort: "Rebase Abort"
        case .mergeAbort: "Merge Abort"
        case .cherryPickAbort: "Cherry-Pick Abort"
        case .cherryPickContinue: "Cherry-Pick Continue"
        case .revertAbort: "Revert Abort"
        case .rebaseContinue: "Rebase Continue"
        case .rebaseSkip: "Rebase Skip"
        }
    }

    func isVisible(in state: GitBranchOperationState) -> Bool {
        switch self {
        case .rebaseAbort, .rebaseContinue, .rebaseSkip: state.isRebasing
        case .mergeAbort: state.isMerging
        case .cherryPickAbort, .cherryPickContinue: state.isCherryPicking
        case .revertAbort: state.isReverting
        }
    }
}

nonisolated enum BranchesPopupSectionID: String, Hashable, CaseIterable, Identifiable {
    case recent
    case local
    case remote
    case tags

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent: "Recent"
        case .local: "Local"
        case .remote: "Remote"
        case .tags: "Tags"
        }
    }
}

nonisolated enum BranchesPopupItemID: Hashable {
    case section(BranchesPopupSectionID)
    case group(BranchesPopupSectionID, String)
    case ref(BranchesPopupSectionID, String)
    case action(BranchesPopupActionID)
    case ongoing(BranchesPopupOngoingAction)
    case separator(String)
}

nonisolated struct BranchesPopupNode: Identifiable, Hashable {
    nonisolated enum Kind: Hashable {
        case ref
        case group
    }

    let id: BranchesPopupItemID
    let kind: Kind
    let title: String
    let detail: String?
    let ref: BranchesPopupRef?
    let children: [BranchesPopupNode]
}

nonisolated struct BranchesPopupSection: Identifiable, Hashable {
    let id: BranchesPopupSectionID
    let nodes: [BranchesPopupNode]
    let refs: [BranchesPopupRef]

    var title: String { id.title }
}

nonisolated struct BranchesPopupTreeInput {
    var localBranches: [GitBranch]
    var remoteBranches: [GitBranch]
    var tags: [GitTag]
    var recentNames: [String]
    var currentBranchName: String?
    var showsRecentBranches: Bool
    var showsTags: Bool
    var query: String
    var favorites: Set<String> = []
    var groupsByDirectory: Bool = true
}

nonisolated struct BranchesPopupRefOrdering {
    let favorites: Set<String>
    let groupsByDirectory: Bool

    func isPinned(_ ref: BranchesPopupRef) -> Bool {
        ref.isCurrent || favorites.contains(ref.id)
    }

    func compare(_ lhs: BranchesPopupRef, _ rhs: BranchesPopupRef) -> Int {
        if lhs.isCurrent != rhs.isCurrent { return lhs.isCurrent ? -1 : 1 }
        let lhsFavorite = favorites.contains(lhs.id)
        let rhsFavorite = favorites.contains(rhs.id)
        if lhsFavorite != rhsFavorite { return lhsFavorite ? -1 : 1 }
        if groupsByDirectory {
            let lhsNested = lhs.shortName.contains("/")
            let rhsNested = rhs.shortName.contains("/")
            if lhsNested != rhsNested { return lhsNested ? -1 : 1 }
        }
        return lhs.shortName.naturalCompare(rhs.shortName)
    }

    func sorted(_ refs: [BranchesPopupRef]) -> [BranchesPopupRef] {
        refs.enumerated()
            .sorted { lhs, rhs in
                let result = compare(lhs.element, rhs.element)
                return result != 0 ? result < 0 : lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    func arrangedChildren(_ nodes: [BranchesPopupNode]) -> [BranchesPopupNode] {
        let pinned = nodes.filter { $0.kind == .ref && $0.ref.map(isPinned) == true }
        let groups = nodes.filter { $0.kind == .group }
        let others = nodes.filter { $0.kind == .ref && $0.ref.map(isPinned) != true }
        return pinned + groups + others
    }
}

nonisolated enum BranchesPopupTreeBuilder {
    static let maxRecentBranches = 5

    static func build(_ input: BranchesPopupTreeInput) -> [BranchesPopupSection] {
        let matcher = BranchesPopupMatcher(query: input.query)
        let ordering = BranchesPopupRefOrdering(
            favorites: input.favorites,
            groupsByDirectory: input.groupsByDirectory
        )

        let localRefs = input.localBranches.map { branch in
            BranchesPopupRef(
                kind: .local,
                name: branch.name,
                shortName: branch.name,
                upstream: branch.upstream,
                isCurrent: branch.name == input.currentBranchName,
                ahead: branch.ahead,
                behind: branch.behind
            )
        }
        let localRefsByName = Dictionary(localRefs.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })

        var recentRefs: [BranchesPopupRef] = []
        if input.showsRecentBranches {
            var seenNames = Set<String>()
            for name in input.recentNames {
                guard recentRefs.count < maxRecentBranches else { break }
                guard let ref = localRefsByName[name], seenNames.insert(name).inserted else { continue }
                recentRefs.append(ref)
            }
        }
        let recentShortNames = Set(recentRefs.map(\.shortName))

        let remoteRefs = input.remoteBranches.compactMap { branch -> BranchesPopupRef? in
            guard let parts = remoteParts(for: branch), parts.name != "HEAD" else { return nil }
            return BranchesPopupRef(
                kind: .remote,
                name: parts.name,
                shortName: "\(parts.remote)/\(parts.name)",
                upstream: nil,
                isCurrent: false
            )
        }

        let tagRefs: [BranchesPopupRef] = input.showsTags
            ? input.tags.map { tag in
                BranchesPopupRef(kind: .tag, name: tag.name, shortName: tag.name, upstream: nil, isCurrent: false)
            }
            : []

        let candidates: [(BranchesPopupSectionID, [BranchesPopupRef])] = [
            (.recent, recentRefs),
            (.local, ordering.sorted(localRefs.filter { !recentShortNames.contains($0.shortName) })),
            (.remote, ordering.sorted(remoteRefs)),
            (.tags, ordering.sorted(tagRefs))
        ]
        return candidates.compactMap { id, refs in
            let matched = matcher.map { matcher in refs.filter { matcher.matches($0.shortName) } } ?? refs
            guard !matched.isEmpty else { return nil }
            return BranchesPopupSection(
                id: id,
                nodes: nodes(for: matched, section: id, ordering: ordering),
                refs: matched
            )
        }
    }

    static func remoteParts(for branch: GitBranch) -> (remote: String, name: String)? {
        var fullName = branch.name
        if branch.longName.hasPrefix("refs/remotes/") {
            fullName = String(branch.longName.dropFirst("refs/remotes/".count))
        }
        let parts = fullName.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2, !parts[1].isEmpty else { return nil }
        return (parts[0], parts[1])
    }

    static func refNode(_ ref: BranchesPopupRef, section: BranchesPopupSectionID, title: String) -> BranchesPopupNode {
        BranchesPopupNode(
            id: ref.itemID(in: section),
            kind: .ref,
            title: title,
            detail: ref.kind == .local ? ref.upstream : nil,
            ref: ref,
            children: []
        )
    }

    private static func nodes(
        for refs: [BranchesPopupRef],
        section: BranchesPopupSectionID,
        ordering: BranchesPopupRefOrdering
    ) -> [BranchesPopupNode] {
        guard ordering.groupsByDirectory else {
            return refs.map { refNode($0, section: section, title: $0.displayName) }
        }
        return buildLevel(
            entries: refs.map { RefEntry(ref: $0, path: $0.displayName.split(separator: "/").map(String.init)) },
            section: section,
            path: [],
            ordering: ordering
        )
    }

    nonisolated private struct RefEntry {
        let ref: BranchesPopupRef
        let path: [String]
    }

    nonisolated private enum Slot {
        case ref(RefEntry)
        case group(String)
    }

    private static func buildLevel(
        entries: [RefEntry],
        section: BranchesPopupSectionID,
        path: [String],
        ordering: BranchesPopupRefOrdering
    ) -> [BranchesPopupNode] {
        var slots: [Slot] = []
        var groups: [String: [RefEntry]] = [:]
        for entry in entries {
            guard let first = entry.path.first else { continue }
            if entry.path.count <= 1 {
                slots.append(.ref(entry))
            } else {
                if groups[first] == nil { slots.append(.group(first)) }
                groups[first, default: []].append(RefEntry(ref: entry.ref, path: Array(entry.path.dropFirst())))
            }
        }

        let isNested = !path.isEmpty
        let nodes = slots.map { slot -> BranchesPopupNode in
            switch slot {
            case .ref(let entry):
                return refNode(entry.ref, section: section, title: entry.path.first ?? entry.ref.displayName)
            case .group(let name):
                let groupPath = path + [name]
                let children = buildLevel(
                    entries: groups[name] ?? [],
                    section: section,
                    path: groupPath,
                    ordering: ordering
                )
                return BranchesPopupNode(
                    id: .group(section, groupPath.joined(separator: "/")),
                    kind: .group,
                    title: name,
                    detail: nil,
                    ref: nil,
                    children: children
                )
            }
        }
        return isNested ? ordering.arrangedChildren(nodes) : nodes
    }
}

nonisolated struct BranchesPopupPreferredRef: Equatable {
    let section: BranchesPopupSectionID
    let ref: BranchesPopupRef

    var itemID: BranchesPopupItemID {
        ref.itemID(in: section)
    }
}

nonisolated enum BranchesPopupPreferredSelection {
    static let searchOrder: [BranchesPopupSectionID] = [.recent, .local, .remote, .tags]

    static func resolve(
        sections: [BranchesPopupSection],
        matcher: BranchesPopupMatcher?,
        recentNames: [String]
    ) -> BranchesPopupPreferredRef? {
        guard let matcher else {
            return previousOrCurrent(sections: sections, recentNames: recentNames)
        }
        for id in searchOrder {
            guard let section = sections.first(where: { $0.id == id }),
                  let ref = topMatch(in: section.refs, matcher: matcher) else { continue }
            return BranchesPopupPreferredRef(section: id, ref: ref)
        }
        return nil
    }

    static func topMatch(in refs: [BranchesPopupRef], matcher: BranchesPopupMatcher) -> BranchesPopupRef? {
        var best: (ref: BranchesPopupRef, weight: Int)?
        for ref in refs {
            guard let weight = matcher.weight(ref.shortName) else { continue }
            if let current = best, current.weight >= weight { continue }
            best = (ref, weight)
        }
        return best?.ref
    }

    private static func previousOrCurrent(
        sections: [BranchesPopupSection],
        recentNames: [String]
    ) -> BranchesPopupPreferredRef? {
        let localCandidates: [BranchesPopupPreferredRef] = sections
            .filter { $0.id == .recent || $0.id == .local }
            .flatMap { section in section.refs.map { BranchesPopupPreferredRef(section: section.id, ref: $0) } }
        for name in recentNames {
            if let match = localCandidates.first(where: { $0.ref.name == name && !$0.ref.isCurrent }) {
                return match
            }
        }
        return localCandidates.first { $0.ref.isCurrent }
    }
}

nonisolated enum BranchesPopupReflogParser {
    static let reflogEntryCount = 50
    private static let checkoutPrefix = "checkout: moving from "
    private static let toSeparator = " to "
    private static let localBranchPrefix = "refs/heads/"

    static func recentBranchNames(from output: String, existingBranches: Set<String>, limit: Int) -> [String] {
        var names: [String] = []
        var seenNames = Set<String>()
        for line in output.components(separatedBy: .newlines) {
            guard names.count < limit else { break }
            let entry = line.trimmingCharacters(in: .whitespaces)
            guard entry.hasPrefix(checkoutPrefix),
                  let separatorRange = entry.range(of: toSeparator, options: .backwards) else { continue }
            let name = String(entry[separatorRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            guard existingBranches.contains(name), seenNames.insert(name).inserted else { continue }
            names.append(name)
        }
        return names
    }

    static func localBranchNames(fromRefs output: String) -> Set<String> {
        var names = Set<String>()
        for line in output.components(separatedBy: .newlines) {
            let ref = line.trimmingCharacters(in: .whitespaces)
            guard ref.hasPrefix(localBranchPrefix) else { continue }
            names.insert(String(ref.dropFirst(localBranchPrefix.count)))
        }
        return names
    }
}

nonisolated enum BranchesPopupRowKind: Hashable {
    case action
    case separator
    case section
    case group
    case ref
}

nonisolated struct BranchesPopupRow: Identifiable, Hashable {
    let id: BranchesPopupItemID
    let kind: BranchesPopupRowKind
    let title: String
    let iconName: String?
    let shortcut: String?
    let detail: String?
    let counters: String?
    let matchRanges: [Range<Int>]
    let depth: Int
    let isExpanded: Bool
    let ref: BranchesPopupRef?
    let action: BranchesPopupActionID?
    let ongoingAction: BranchesPopupOngoingAction?
    let isFavorite: Bool

    var isSelectable: Bool { kind != .separator }
}
