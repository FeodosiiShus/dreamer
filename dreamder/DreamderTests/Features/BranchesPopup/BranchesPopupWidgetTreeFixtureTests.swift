import Foundation
import Testing
@testable import Dreamder

nonisolated enum WidgetTreePrinter {
    static let separator = "------"

    static func render(_ input: BranchesPopupTreeInput) -> String {
        var lines = actionLines(query: input.query)
        for section in BranchesPopupTreeBuilder.build(input) {
            lines.append("-\(section.title)")
            append(section.nodes, depth: 1, favorites: input.favorites, to: &lines)
        }
        return lines.joined(separator: "\n")
    }

    static func normalizeSnapshot(_ text: String) -> String {
        text
            .replacingOccurrences(of: "...", with: "")
            .replacingOccurrences(of: "…", with: "")
            .trimmingCharacters(in: .newlines)
    }

    private static func actionLines(query: String) -> [String] {
        let matcher = BranchesPopupMatcher(query: query)
        let actions = BranchesPopupActionID.allCases.filter { action in
            matcher.map { $0.matches(action.title) } ?? true
        }
        var lines: [String] = []
        for action in actions {
            if action == .newBranch, !lines.isEmpty {
                lines.append(separator)
            }
            lines.append("-" + action.title.replacingOccurrences(of: "…", with: ""))
        }
        if !actions.isEmpty {
            lines.append(separator)
        }
        return lines
    }

    private static func append(
        _ nodes: [BranchesPopupNode],
        depth: Int,
        favorites: Set<String>,
        to lines: inout [String]
    ) {
        let indent = String(repeating: " ", count: depth)
        for node in nodes {
            let expandMarker = node.kind == .group ? "-" : ""
            lines.append("\(indent)\(expandMarker)\(node.title) [\(icon(for: node, favorites: favorites))]")
            append(node.children, depth: depth + 1, favorites: favorites, to: &lines)
        }
    }

    private static func icon(for node: BranchesPopupNode, favorites: Set<String>) -> String {
        guard let ref = node.ref else { return "nodes/folder.svg" }
        let isFavorite = favorites.contains(ref.id)
        switch (ref.iconName, isFavorite) {
        case ("vcs/currentBranchLabel", true): return "icons/currentBranchFavoriteLabel.svg"
        case ("vcs/currentBranchLabel", false): return "icons/currentBranchLabel.svg"
        case (_, true): return "nodes/favorite.svg"
        case ("vcs/branchLabel", false): return "icons/branchLabel.svg"
        default: return "vcs/branchNode.svg"
        }
    }
}

@Suite
struct BranchesPopupWidgetTreeFixtureTests {
    struct Case: Sendable, CustomStringConvertible {
        let name: String
        let input: BranchesPopupTreeInput

        var description: String { name }
    }

    private static let fixtureDirectory = "plugins/git4idea/testData/widgetTree"

    private static let multiRepositoryFixtures: Set<String> = [
        "MultiRepo",
        "MultiRepoNotFavoriteCurrentBranch",
        "MultiRepoWithFavoriteRefs",
        "MultiRepoWithFilter",
        "MultiRepoWithFilterMatchingRepo",
        "MultiRepoWithoutSync",
        "MultiRepoWithoutSyncWithFilter",
        "MultipleFreshRepos",
        "MultipleFreshReposNoSync"
    ]

    private static func local(_ name: String) -> GitBranch {
        GitBranch(name: name, longName: "refs/heads/\(name)", upstream: nil, ahead: 0, behind: 0)
    }

    private static func remote(_ name: String) -> GitBranch {
        GitBranch(name: name, longName: "refs/remotes/\(name)", upstream: nil, ahead: 0, behind: 0)
    }

    private static func tag(_ name: String) -> GitTag {
        GitTag(name: name, objectName: "")
    }

    private static let createdLocalNames = ["test", "group/test", "another/group/test"]
    private static let createdRemoteNames = [
        "origin/master", "origin/test", "origin/group/test", "origin/another/group/test"
    ]
    private static let defaultFavorites: Set<String> = ["local:master", "remote:origin/master"]

    private static func input(
        locals: [String],
        remotes: [String] = [],
        tags: [String] = [],
        recent: [String] = [],
        current: String,
        query: String = "",
        favorites: Set<String> = defaultFavorites
    ) -> BranchesPopupTreeInput {
        BranchesPopupTreeInput(
            localBranches: locals.map(local),
            remoteBranches: remotes.map(remote),
            tags: tags.map(tag),
            recentNames: recent,
            currentBranchName: current,
            showsRecentBranches: true,
            showsTags: true,
            query: query,
            favorites: favorites
        )
    }

    static let cases: [Case] = [
        Case(
            name: "SingleRepo",
            input: input(
                locals: ["master", "another-branch"] + createdLocalNames,
                remotes: createdRemoteNames,
                recent: ["another-branch"],
                current: "another-branch"
            )
        ),
        Case(
            name: "SingleRepoWithTags",
            input: input(
                locals: ["master"] + createdLocalNames,
                remotes: createdRemoteNames,
                tags: ["v1", "group/v2"],
                current: "master"
            )
        ),
        Case(
            name: "SingleRepoFiltering",
            input: input(
                locals: ["master", "update"] + createdLocalNames,
                remotes: createdRemoteNames,
                tags: ["v1", "group/v2"],
                recent: ["update"],
                current: "update",
                query: "update"
            )
        ),
        Case(
            name: "SingleRepoWithFavoriteRefsSorted",
            input: input(
                locals: ["master", "a", "b", "c", "Bb", "d", "e-group/a", "f-group/a", "f-group/b"],
                remotes: ["origin/master"],
                tags: ["a-tag", "b-tag", "c-tag"],
                current: "master",
                favorites: defaultFavorites.union(["local:d", "tag:c-tag"])
            )
        ),
        Case(
            name: "SingleFreshRepo",
            input: input(locals: ["master"], current: "master", favorites: ["local:master"])
        )
    ]

    @Test(arguments: cases)
    func printedTreeMatchesIntelliJSnapshot(fixture: Case) throws {
        let expected = try IntelliJTestData.text("\(Self.fixtureDirectory)/\(fixture.name)")
        let printed = WidgetTreePrinter.render(fixture.input)
        #expect(
            WidgetTreePrinter.normalizeSnapshot(printed)
                == WidgetTreePrinter.normalizeSnapshot(expected)
        )
    }

    @Test
    func everyFixtureIsEitherPortedOrKnownMultiRepository() throws {
        let onDisk = Set(try IntelliJTestData.files(in: Self.fixtureDirectory, suffix: ""))
        let ported = Set(Self.cases.map(\.name))
        #expect(onDisk == ported.union(Self.multiRepositoryFixtures))
        #expect(ported.isDisjoint(with: Self.multiRepositoryFixtures))
    }
}
