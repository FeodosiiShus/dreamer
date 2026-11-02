import Foundation

struct GitTag: Hashable, Identifiable {
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

struct BranchesPopupRef: Hashable, Identifiable {
    enum Kind: Hashable {
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

enum BranchesPopupActionID: String, CaseIterable, Hashable, Identifiable {
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

enum BranchesPopupOngoingAction: String, CaseIterable, Hashable, Identifiable {
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

enum BranchesPopupSectionID: String, Hashable, CaseIterable, Identifiable {
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

enum BranchesPopupItemID: Hashable {
    case section(BranchesPopupSectionID)
    case group(BranchesPopupSectionID, String)
    case ref(BranchesPopupSectionID, String)
    case action(BranchesPopupActionID)
    case ongoing(BranchesPopupOngoingAction)
    case separator(String)
}

struct BranchesPopupNode: Identifiable, Hashable {
    enum Kind: Hashable {
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

struct BranchesPopupSection: Identifiable, Hashable {
    let id: BranchesPopupSectionID
    let nodes: [BranchesPopupNode]

    var title: String { id.title }
}

struct BranchesPopupTreeInput {
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

enum BranchesPopupTreeBuilder {
    static func build(_ input: BranchesPopupTreeInput) -> [BranchesPopupSection] {
        let query = input.query.trimmingCharacters(in: .whitespaces)
        let isSearching = !query.isEmpty

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
            for name in input.recentNames where !seenNames.contains(name) {
                guard let ref = localRefsByName[name] else { continue }
                seenNames.insert(name)
                recentRefs.append(ref)
            }
        }
        let recentShortNames = Set(recentRefs.map(\.shortName))
        if isSearching {
            recentRefs = recentRefs.filter { matches(query, ref: $0) }
        }

        let localRefsForSection = localRefs
            .filter { ref in
                guard !recentShortNames.contains(ref.shortName) else { return false }
                guard isSearching else { return true }
                return matches(query, ref: ref)
            }
            .sorted(by: refOrder(favorites: input.favorites, currentName: input.currentBranchName))

        let remoteRefs = input.remoteBranches
            .compactMap { branch -> BranchesPopupRef? in
                guard let parts = remoteParts(for: branch), parts.name != "HEAD" else { return nil }
                return BranchesPopupRef(
                    kind: .remote,
                    name: parts.name,
                    shortName: "\(parts.remote)/\(parts.name)",
                    upstream: nil,
                    isCurrent: false
                )
            }
            .filter { ref in
                guard isSearching else { return true }
                return matches(query, ref: ref)
            }

        var tagRefs: [BranchesPopupRef] = []
        if input.showsTags {
            tagRefs = input.tags
                .map { tag in
                    BranchesPopupRef(
                        kind: .tag,
                        name: tag.name,
                        shortName: tag.name,
                        upstream: nil,
                        isCurrent: false
                    )
                }
                .filter { ref in
                    guard isSearching else { return true }
                    return matches(query, ref: ref)
                }
        }

        var sections: [BranchesPopupSection] = []
        if !recentRefs.isEmpty {
            sections.append(BranchesPopupSection(
                id: .recent,
                nodes: nodes(
                    for: recentRefs,
                    section: .recent,
                    groupsByDirectory: input.groupsByDirectory,
                    favorites: input.favorites,
                    currentName: input.currentBranchName,
                    preservesOrder: true
                )
            ))
        }
        if !localRefsForSection.isEmpty {
            sections.append(BranchesPopupSection(
                id: .local,
                nodes: nodes(
                    for: localRefsForSection,
                    section: .local,
                    groupsByDirectory: input.groupsByDirectory,
                    favorites: input.favorites,
                    currentName: input.currentBranchName,
                    preservesOrder: false
                )
            ))
        }
        if !remoteRefs.isEmpty {
            sections.append(BranchesPopupSection(
                id: .remote,
                nodes: nodes(
                    for: remoteRefs,
                    section: .remote,
                    groupsByDirectory: input.groupsByDirectory,
                    favorites: input.favorites,
                    currentName: input.currentBranchName,
                    preservesOrder: false
                )
            ))
        }
        if !tagRefs.isEmpty {
            sections.append(BranchesPopupSection(
                id: .tags,
                nodes: nodes(
                    for: tagRefs,
                    section: .tags,
                    groupsByDirectory: input.groupsByDirectory,
                    favorites: input.favorites,
                    currentName: input.currentBranchName,
                    preservesOrder: false
                )
            ))
        }
        return sections
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
        groupsByDirectory: Bool,
        favorites: Set<String>,
        currentName: String?,
        preservesOrder: Bool
    ) -> [BranchesPopupNode] {
        let ordered: [BranchesPopupRef]
        if preservesOrder {
            ordered = refs
        } else {
            ordered = refs.sorted(by: refOrder(favorites: favorites, currentName: currentName))
        }
        guard groupsByDirectory else {
            return ordered.map { refNode($0, section: section, title: $0.displayName) }
        }
        return buildLevel(
            entries: ordered.map { RefEntry(ref: $0, path: $0.displayName.split(separator: "/").map(String.init)) },
            section: section,
            path: [],
            favorites: favorites,
            currentName: currentName,
            preservesOrder: preservesOrder
        )
    }

    private struct RefEntry {
        let ref: BranchesPopupRef
        let path: [String]
    }

    private static func buildLevel(
        entries: [RefEntry],
        section: BranchesPopupSectionID,
        path: [String],
        favorites: Set<String>,
        currentName: String?,
        preservesOrder: Bool
    ) -> [BranchesPopupNode] {
        var direct: [RefEntry] = []
        var groups: [String: [RefEntry]] = [:]
        for entry in entries {
            guard let first = entry.path.first else { continue }
            if entry.path.count <= 1 {
                direct.append(entry)
            } else {
                groups[first, default: []].append(RefEntry(ref: entry.ref, path: Array(entry.path.dropFirst())))
            }
        }

        if !preservesOrder {
            direct.sort { refOrder(favorites: favorites, currentName: currentName)($0.ref, $1.ref) }
        }
        var nodes: [BranchesPopupNode] = direct
            .map { refNode($0.ref, section: section, title: $0.path.first ?? $0.ref.displayName) }

        let groupNames = preservesOrder ? Array(groups.keys) : groups.keys.sorted()
        for name in groupNames {
            let children = buildLevel(
                entries: groups[name] ?? [],
                section: section,
                path: path + [name],
                favorites: favorites,
                currentName: currentName,
                preservesOrder: preservesOrder
            )
            let groupID = BranchesPopupItemID.group(section, (path + [name]).joined(separator: "/"))
            nodes.append(BranchesPopupNode(
                id: groupID,
                kind: .group,
                title: name,
                detail: nil,
                ref: nil,
                children: children
            ))
        }
        return nodes
    }

    private static func matches(_ query: String, ref: BranchesPopupRef) -> Bool {
        BranchesPopupMatcher.matches(query: query, candidate: ref.shortName)
    }

    private static func refOrder(
        favorites: Set<String>,
        currentName: String?
    ) -> (BranchesPopupRef, BranchesPopupRef) -> Bool {
        { lhs, rhs in
            if lhs.isCurrent != rhs.isCurrent { return lhs.isCurrent }
            let lhsFavorite = favorites.contains(lhs.id)
            let rhsFavorite = favorites.contains(rhs.id)
            if lhsFavorite != rhsFavorite { return lhsFavorite }
            return nameOrder(lhs, rhs)
        }
    }

    private static func nameOrder(_ lhs: BranchesPopupRef, _ rhs: BranchesPopupRef) -> Bool {
        let lhsKey = lhs.displayName.lowercased()
        let rhsKey = rhs.displayName.lowercased()
        if lhsKey != rhsKey { return lhsKey < rhsKey }
        return lhs.displayName < rhs.displayName
    }
}

enum BranchesPopupReflogParser {
    static func recentBranchNames(from output: String, limit: Int) -> [String] {
        var names: [String] = []
        var seenNames = Set<String>()
        for line in output.components(separatedBy: .newlines) {
            let entry = line.trimmingCharacters(in: .whitespaces)
            let prefix = "checkout: moving from "
            guard entry.hasPrefix(prefix) else { continue }
            let rest = entry.dropFirst(prefix.count)
            guard let separatorRange = rest.range(of: " to ") else { continue }
            let name = String(rest[separatorRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, name != "HEAD", !name.hasPrefix("refs/"), !seenNames.contains(name) else { continue }
            seenNames.insert(name)
            names.append(name)
            if names.count >= limit { break }
        }
        return names
    }
}

enum BranchesPopupRowKind: Hashable {
    case action
    case separator
    case section
    case group
    case ref
}

struct BranchesPopupRow: Identifiable, Hashable {
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
