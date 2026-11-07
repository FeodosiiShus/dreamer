import Testing
@testable import Dreamder

@Suite
struct BranchesPopupTreeTests {
    private func local(
        _ name: String,
        upstream: String? = nil,
        ahead: Int = 0,
        behind: Int = 0
    ) -> GitBranch {
        GitBranch(
            name: name,
            longName: "refs/heads/\(name)",
            upstream: upstream,
            ahead: ahead,
            behind: behind
        )
    }

    private func remote(_ name: String) -> GitBranch {
        GitBranch(name: name, longName: "refs/remotes/\(name)", upstream: nil, ahead: 0, behind: 0)
    }

    private func input(
        locals: [GitBranch] = [],
        remotes: [GitBranch] = [],
        tags: [GitTag] = [],
        recent: [String] = [],
        current: String? = nil,
        showsRecent: Bool = true,
        showsTags: Bool = true,
        query: String = "",
        favorites: Set<String> = [],
        groupsByDirectory: Bool = true
    ) -> BranchesPopupTreeInput {
        BranchesPopupTreeInput(
            localBranches: locals,
            remoteBranches: remotes,
            tags: tags,
            recentNames: recent,
            currentBranchName: current,
            showsRecentBranches: showsRecent,
            showsTags: showsTags,
            query: query,
            favorites: favorites,
            groupsByDirectory: groupsByDirectory
        )
    }

    private func refs(in section: BranchesPopupSection?) -> [BranchesPopupRef] {
        func collect(_ nodes: [BranchesPopupNode]) -> [BranchesPopupRef] {
            nodes.flatMap { node in
                if let ref = node.ref { return [ref] }
                return collect(node.children)
            }
        }
        return collect(section?.nodes ?? [])
    }

    @Test
    func recentKeepsReflogOrderAndDeduplicates() {
        let sections = BranchesPopupTreeBuilder.build(input(
            locals: [local("main"), local("feature"), local("fix")],
            recent: ["feature", "feature", "fix", "main"],
            current: "main"
        ))
        let recentSection = sections.first { $0.id == .recent }
        #expect(recentSection?.nodes.map(\.title) == ["feature", "fix", "main"])
    }

    @Test
    func recentIsCappedAtFive() {
        let locals = (1...8).map { local("branch\($0)") }
        let sections = BranchesPopupTreeBuilder.build(input(
            locals: locals,
            recent: (1...8).map { "branch\($0)" },
            current: "branch8"
        ))
        let recentSection = sections.first { $0.id == .recent }
        #expect(recentSection?.nodes.count == 5)
        #expect(recentSection?.nodes.first?.title == "branch1")
        #expect(recentSection?.nodes.last?.title == "branch5")
    }

    @Test
    func recentIsHiddenWhenDisabled() {
        let withoutRecent = BranchesPopupTreeBuilder.build(input(
            locals: [local("main")],
            current: "main",
            showsRecent: false
        ))
        #expect(withoutRecent.contains { $0.id == .recent } == false)
    }

    @Test
    func recentRequiresReflogEntries() {
        let sections = BranchesPopupTreeBuilder.build(input(
            locals: [local("main")],
            current: "main"
        ))
        #expect(sections.contains { $0.id == .recent } == false)
        #expect(sections.first { $0.id == .local }?.nodes.map(\.title) == ["main"])
    }

    @Test
    func recentBranchesAreExcludedFromLocal() {
        let sections = BranchesPopupTreeBuilder.build(input(
            locals: [local("main"), local("feature"), local("fix")],
            recent: ["feature", "fix"],
            current: "main"
        ))
        #expect(sections.map(\.id) == [.recent, .local])
        #expect(sections.first { $0.id == .recent }?.nodes.map(\.title) == ["feature", "fix"])
        #expect(sections.first { $0.id == .local }?.nodes.map(\.title) == ["main"])
    }

    @Test
    func localBranchesPutCurrentFirst() {
        let sections = BranchesPopupTreeBuilder.build(input(
            locals: [local("feature"), local("main"), local("fix")],
            current: "main"
        ))
        #expect(sections.map(\.id) == [.local])
        #expect(sections.first?.nodes.map(\.title) == ["main", "feature", "fix"])
    }

    @Test
    func favoritesFloatToTopBelowCurrent() {
        let sections = BranchesPopupTreeBuilder.build(input(
            locals: [local("alpha"), local("feature"), local("main")],
            current: "main",
            favorites: ["local:feature"]
        ))
        #expect(sections.first?.nodes.map(\.title) == ["main", "feature", "alpha"])
    }

    @Test
    func localNamesAreGroupedByDirectory() {
        let sections = BranchesPopupTreeBuilder.build(input(
            locals: [local("feature/login"), local("feature/pay"), local("main")],
            current: "main"
        ))
        let nodes = sections.first { $0.id == .local }?.nodes
        #expect(nodes?.map(\.title) == ["main", "feature"])
        let group = nodes?.first { $0.title == "feature" }
        #expect(group?.kind == .group)
        #expect(group?.children.map(\.title) == ["login", "pay"])
        #expect(group?.id == .group(.local, "feature"))
    }

    @Test
    func directoryGroupingCanBeDisabled() {
        let sections = BranchesPopupTreeBuilder.build(input(
            locals: [local("feature/login"), local("feature/pay"), local("main")],
            current: "main",
            groupsByDirectory: false
        ))
        #expect(sections.first { $0.id == .local }?.nodes.map(\.title) == [
            "main",
            "feature/login",
            "feature/pay"
        ])
    }

    @Test
    func remoteBranchesAreGroupedAndHideHEAD() {
        let sections = BranchesPopupTreeBuilder.build(input(
            remotes: [
                remote("origin/master"),
                remote("origin/feature/login"),
                remote("origin/HEAD"),
                remote("upstream/main")
            ]
        ))
        let remoteSection = sections.first { $0.id == .remote }
        #expect(remoteSection?.nodes.map(\.title) == ["origin", "upstream"])
        let originGroup = remoteSection?.nodes.first { $0.title == "origin" }
        #expect(originGroup?.children.map(\.title) == ["feature", "master"])
        let featureGroup = originGroup?.children.first { $0.title == "feature" }
        #expect(featureGroup?.children.map(\.title) == ["login"])
        let upstreamGroup = remoteSection?.nodes.first { $0.title == "upstream" }
        #expect(upstreamGroup?.children.map(\.title) == ["main"])
    }

    @Test
    func remoteBranchIDsUseRemotePrefixedNames() {
        let sections = BranchesPopupTreeBuilder.build(input(remotes: [remote("origin/main")]))
        let child = sections.first { $0.id == .remote }?.nodes.first?.children.first
        #expect(child?.id == .ref(.remote, "origin/main"))
        #expect(child?.ref?.shortName == "origin/main")
        #expect(child?.ref?.name == "main")
    }

    @Test
    func localBranchesExposeUpstreamAndCounters() {
        let sections = BranchesPopupTreeBuilder.build(input(
            locals: [local("main", upstream: "origin/main", ahead: 2, behind: 1), local("feature")],
            current: "main"
        ))
        let nodes = sections.first { $0.id == .local }?.nodes
        #expect(nodes?.first { $0.title == "main" }?.detail == "origin/main")
        #expect(nodes?.first { $0.title == "main" }?.ref?.counterText == "↑2 ↓1")
        #expect(nodes?.first { $0.title == "feature" }?.detail == nil)
        #expect(nodes?.first?.ref?.isCurrent == true)
    }

    @Test
    func tagsAreShownOnlyWhenEnabled() {
        let tags = [GitTag(name: "v1.0", objectName: "abc"), GitTag(name: "v2.0", objectName: "def")]
        let shown = BranchesPopupTreeBuilder.build(input(tags: tags))
        #expect(shown.first { $0.id == .tags }?.nodes.map(\.title) == ["v1.0", "v2.0"])

        let hidden = BranchesPopupTreeBuilder.build(input(tags: tags, showsTags: false))
        #expect(hidden.contains { $0.id == .tags } == false)
    }

    @Test
    func emptySectionsAreHidden() {
        let sections = BranchesPopupTreeBuilder.build(input(
            locals: [local("main")],
            current: "main"
        ))
        #expect(sections.map(\.id) == [.local])

        let nothing = BranchesPopupTreeBuilder.build(input())
        #expect(nothing.isEmpty)
    }

    @Test
    func filteringKeepsOnlyMatchesAndHidesEmptySections() {
        let sections = BranchesPopupTreeBuilder.build(input(
            locals: [local("main"), local("feature/login"), local("release/1.0")],
            remotes: [remote("origin/main"), remote("origin/feature/login")],
            tags: [GitTag(name: "v1.0", objectName: "abc")],
            current: "main",
            query: "feat"
        ))
        #expect(sections.map(\.id) == [.local, .remote])
        #expect(refs(in: sections.first { $0.id == .local }).map(\.shortName) == ["feature/login"])
        #expect(refs(in: sections.first { $0.id == .remote }).map(\.shortName) == ["origin/feature/login"])
    }

    @Test
    func recentAndLocalRowsHaveDistinctIDs() {
        let sections = BranchesPopupTreeBuilder.build(input(
            locals: [local("main"), local("feature")],
            recent: ["feature"],
            current: "main"
        ))
        let recentIDs = Set(sections.first { $0.id == .recent }?.nodes.map(\.id) ?? [])
        let localIDs = Set(sections.first { $0.id == .local }?.nodes.map(\.id) ?? [])
        #expect(recentIDs == [.ref(.recent, "feature")])
        #expect(localIDs == [.ref(.local, "main")])
        #expect(recentIDs.isDisjoint(with: localIDs))
    }

    @Test
    func searchingDoesNotRepeatRecentBranchesInLocal() {
        let sections = BranchesPopupTreeBuilder.build(input(
            locals: [local("main"), local("feature")],
            remotes: [remote("origin/main")],
            recent: ["feature"],
            current: "main",
            query: "mai"
        ))
        #expect(sections.map(\.id) == [.local, .remote])
        #expect(refs(in: sections.first { $0.id == .local }).map(\.shortName) == ["main"])
        #expect(refs(in: sections.first { $0.id == .remote }).map(\.shortName) == ["origin/main"])
    }

    @Test
    func noMatchProducesNoSections() {
        let sections = BranchesPopupTreeBuilder.build(input(
            locals: [local("main")],
            remotes: [remote("origin/main")],
            tags: [GitTag(name: "v1.0", objectName: "abc")],
            current: "main",
            query: "zzz"
        ))
        #expect(sections.isEmpty)
    }

    @Test
    func reflogParserDeduplicatesAndKeepsOrder() {
        let output = """
        checkout: moving from main to feature
        checkout: moving from feature to fix/login
        checkout: moving from fix/login to feature
        commit: Fix the build
        checkout: moving from feature to HEAD
        checkout: moving from feature to 1a2b3c4
        """
        let existing: Set<String> = ["main", "feature", "fix/login"]
        let names = BranchesPopupReflogParser.recentBranchNames(from: output, existingBranches: existing, limit: 10)
        #expect(names == ["feature", "fix/login"])
    }

    @Test
    func reflogParserSkipsDeletedBranchesBeforeApplyingTheLimit() {
        let output = """
        checkout: moving from a to gone
        checkout: moving from gone to b
        checkout: moving from b to c
        checkout: moving from c to d
        """
        let existing: Set<String> = ["a", "b", "c", "d"]
        #expect(BranchesPopupReflogParser.recentBranchNames(from: output, existingBranches: existing, limit: 2) == ["b", "c"])
        #expect(BranchesPopupReflogParser.recentBranchNames(from: output, existingBranches: existing, limit: 0).isEmpty)
    }

    @Test
    func reflogParserTakesTheNameAfterTheLastSeparator() {
        let output = "checkout: moving from a to b to c"
        let names = BranchesPopupReflogParser.recentBranchNames(from: output, existingBranches: ["c"], limit: 5)
        #expect(names == ["c"])
    }

    @Test
    func localBranchNamesComeFromFullRefNames() {
        let output = "refs/heads/main\nrefs/heads/feature/login\nrefs/remotes/origin/main\n\n"
        #expect(BranchesPopupReflogParser.localBranchNames(fromRefs: output) == ["main", "feature/login"])
    }

    @Test
    func recentIsCappedAtFiveAfterFilteringMissingBranches() {
        let names = ["a", "b", "c", "d", "e", "f"]
        let sections = BranchesPopupTreeBuilder.build(input(
            locals: names.map { local($0) } + [local("main")],
            recent: ["gone1", "gone2"] + names,
            current: "main"
        ))
        #expect(BranchesPopupTreeBuilder.maxRecentBranches == 5)
        #expect(sections.first { $0.id == .recent }?.nodes.map(\.title) == ["a", "b", "c", "d", "e"])
        #expect(sections.first { $0.id == .local }?.nodes.map(\.title) == ["main", "f"])
    }

    @Test
    func currentBranchInRecentIsNotRepeatedInLocal() {
        let sections = BranchesPopupTreeBuilder.build(input(
            locals: [local("main"), local("feature"), local("fix")],
            recent: ["main", "feature", "main", "feature"],
            current: "main"
        ))
        let all = sections.flatMap(\.refs)
        #expect(all.filter { $0.shortName == "main" }.count == 1)
        #expect(all.filter { $0.shortName == "feature" }.count == 1)
        #expect(sections.first { $0.id == .recent }?.nodes.map(\.title) == ["main", "feature"])
        #expect(sections.first { $0.id == .local }?.nodes.map(\.title) == ["fix"])
    }

    @Test
    func currentBranchBeyondTheRecentCapStaysInLocalOnce() {
        let names = (1...7).map { "branch\($0)" }
        let sections = BranchesPopupTreeBuilder.build(input(
            locals: names.map { local($0) },
            recent: names,
            current: "branch7"
        ))
        let all = sections.flatMap(\.refs)
        #expect(all.filter { $0.shortName == "branch7" }.count == 1)
        #expect(sections.first { $0.id == .local }?.nodes.map(\.title) == ["branch7", "branch6"])
    }

    @Test
    func sectionsAppearAsRecentLocalRemoteTags() {
        let sections = BranchesPopupTreeBuilder.build(input(
            locals: [local("main"), local("feature")],
            remotes: [remote("origin/main")],
            tags: [GitTag(name: "v1", objectName: "abc")],
            recent: ["feature"],
            current: "main"
        ))
        #expect(sections.map(\.id) == [.recent, .local, .remote, .tags])
    }

    @Test
    func namesAreOrderedNaturallyAndCaseInsensitively() {
        let sections = BranchesPopupTreeBuilder.build(input(
            locals: [local("branch10"), local("branch2"), local("Branch1"), local("Alpha")],
            groupsByDirectory: false
        ))
        #expect(sections.first?.nodes.map(\.title) == ["Alpha", "Branch1", "branch2", "branch10"])
    }

    @Test
    func tagsAreOrderedNaturally() {
        let tags = ["v10", "v2", "v1"].map { GitTag(name: $0, objectName: "abc") }
        let sections = BranchesPopupTreeBuilder.build(input(tags: tags))
        #expect(sections.first { $0.id == .tags }?.nodes.map(\.title) == ["v1", "v2", "v10"])
    }

    @Test
    func currentThenFavoritesThenGroupsThenOtherNames() {
        let sections = BranchesPopupTreeBuilder.build(input(
            locals: [local("feature/a"), local("release/1"), local("zeta"), local("alpha"), local("main")],
            current: "main",
            favorites: ["local:zeta"]
        ))
        #expect(sections.first?.nodes.map(\.title) == ["main", "zeta", "feature", "release", "alpha"])
    }

    @Test
    func favoriteBranchInsideAGroupFloatsItsGroup() {
        let sections = BranchesPopupTreeBuilder.build(input(
            locals: [local("alpha/one"), local("beta/two"), local("gamma/three"), local("main")],
            current: "main",
            favorites: ["local:gamma/three"]
        ))
        #expect(sections.first?.nodes.map(\.title) == ["main", "gamma", "alpha", "beta"])
    }

    @Test
    func currentBranchInsideAGroupFloatsItsGroup() {
        let sections = BranchesPopupTreeBuilder.build(input(
            locals: [local("alpha/one"), local("beta/two"), local("gamma/three")],
            current: "beta/two"
        ))
        #expect(sections.first?.nodes.map(\.title) == ["beta", "alpha", "gamma"])
    }

    @Test
    func groupChildrenListPinnedRefsThenGroupsThenOtherRefs() {
        let sections = BranchesPopupTreeBuilder.build(input(
            locals: [local("g/b"), local("g/a"), local("g/sub/x"), local("g/fav")],
            favorites: ["local:g/fav"]
        ))
        let group = sections.first?.nodes.first
        #expect(group?.id == .group(.local, "g"))
        #expect(group?.children.map(\.title) == ["fav", "sub", "a", "b"])
        #expect(group?.children.first { $0.title == "sub" }?.id == .group(.local, "g/sub"))
    }

    @Test
    func groupsAreOrderedNaturally() {
        let sections = BranchesPopupTreeBuilder.build(input(
            locals: [local("r/10/x"), local("r/2/x"), local("r/1/x")]
        ))
        let group = sections.first?.nodes.first
        #expect(group?.children.map(\.title) == ["1", "2", "10"])
    }

    @Test
    func recentGroupsFollowReflogOrder() {
        let sections = BranchesPopupTreeBuilder.build(input(
            locals: [local("zed/a"), local("alpha/b"), local("main")],
            recent: ["zed/a", "main", "alpha/b"],
            current: "main"
        ))
        #expect(sections.first { $0.id == .recent }?.nodes.map(\.title) == ["zed", "main", "alpha"])
    }

    @Test
    func sectionRefsListTheSortedMatchingReferences() {
        let sections = BranchesPopupTreeBuilder.build(input(
            locals: [local("zeta"), local("g/b"), local("alpha")],
            current: "alpha"
        ))
        let localSection = sections.first { $0.id == .local }
        #expect(localSection?.refs.map(\.shortName) == ["alpha", "g/b", "zeta"])
        #expect(localSection?.nodes.map(\.title) == ["alpha", "g", "zeta"])
    }

    private func preferred(
        _ input: BranchesPopupTreeInput,
        query: String? = nil
    ) -> BranchesPopupPreferredRef? {
        var treeInput = input
        if let query { treeInput.query = query }
        return BranchesPopupPreferredSelection.resolve(
            sections: BranchesPopupTreeBuilder.build(treeInput),
            matcher: BranchesPopupMatcher(query: treeInput.query),
            recentNames: treeInput.recentNames
        )
    }

    @Test
    func withoutQueryThePreviousRecentBranchIsPreferred() {
        let result = preferred(input(
            locals: [local("main"), local("feature"), local("fix")],
            recent: ["main", "fix", "feature"],
            current: "main"
        ))
        #expect(result?.ref.shortName == "fix")
        #expect(result?.section == .recent)
        #expect(result?.itemID == .ref(.recent, "fix"))
    }

    @Test
    func withoutQueryTheCurrentBranchIsPreferredWhenNothingWasCheckedOutBefore() {
        let onlyCurrentRecent = preferred(input(
            locals: [local("main"), local("feature")],
            recent: ["main"],
            current: "main"
        ))
        #expect(onlyCurrentRecent?.ref.shortName == "main")
        #expect(onlyCurrentRecent?.section == .recent)

        let noRecent = preferred(input(
            locals: [local("main"), local("feature")],
            current: "main"
        ))
        #expect(noRecent?.ref.shortName == "main")
        #expect(noRecent?.section == .local)
    }

    @Test
    func withoutQueryThePreviousBranchIsFoundEvenWhenRecentIsHidden() {
        let result = preferred(input(
            locals: [local("main"), local("feature")],
            recent: ["main", "feature"],
            current: "main",
            showsRecent: false
        ))
        #expect(result?.ref.shortName == "feature")
        #expect(result?.section == .local)
    }

    @Test
    func withoutQueryAndWithoutCurrentNothingIsPreferred() {
        #expect(preferred(input(locals: [local("feature")])) == nil)
    }

    @Test
    func queryPrefersRecentThenLocalThenRemoteThenTags() {
        let all = input(
            locals: [local("main"), local("feature/main")],
            remotes: [remote("origin/main")],
            tags: [GitTag(name: "main-tag", objectName: "abc")],
            recent: ["feature/main"],
            current: "main"
        )
        let recentWins = preferred(all, query: "main")
        #expect(recentWins?.section == .recent)
        #expect(recentWins?.ref.shortName == "feature/main")

        var withoutRecent = all
        withoutRecent.recentNames = []
        let localWins = preferred(withoutRecent, query: "main")
        #expect(localWins?.section == .local)

        var remoteAndTag = all
        remoteAndTag.localBranches = []
        remoteAndTag.recentNames = []
        let remoteWins = preferred(remoteAndTag, query: "main")
        #expect(remoteWins?.section == .remote)
        #expect(remoteWins?.ref.shortName == "origin/main")

        var tagOnly = remoteAndTag
        tagOnly.remoteBranches = []
        let tagWins = preferred(tagOnly, query: "main")
        #expect(tagWins?.section == .tags)
        #expect(tagWins?.ref.shortName == "main-tag")
    }

    @Test
    func queryPicksTheHighestWeightInsideTheFirstMatchingSection() {
        let result = preferred(
            input(locals: [local("release/feature/login"), local("feature/login"), local("login")], current: "other"),
            query: "login"
        )
        #expect(result?.section == .local)
        #expect(result?.ref.shortName == "login")
    }

    @Test
    func queryTiesKeepTheFirstReferenceInSortedOrder() {
        let result = preferred(
            input(locals: [local("release/2"), local("release/1")]),
            query: "rel"
        )
        #expect(result?.ref.shortName == "release/1")
    }

    @Test
    func queryWithoutMatchesPrefersNothing() {
        #expect(preferred(input(locals: [local("main")], current: "main"), query: "zzz") == nil)
    }

    @Test
    func slashQueryIsTreatedAsNoQuery() {
        let result = preferred(input(
            locals: [local("main"), local("feature")],
            recent: ["main", "feature"],
            current: "main"
        ), query: "/")
        #expect(result?.ref.shortName == "feature")
        let sections = BranchesPopupTreeBuilder.build(input(locals: [local("main"), local("feature")], query: "/"))
        #expect(sections.first?.refs.count == 2)
    }

    @Test
    func tagListParsesGitOutput() {
        let tags = GitTag.list(from: "v1.0|abc123\nv0.9|def456\n\n")
        #expect(tags.map(\.name) == ["v0.9", "v1.0"])
        #expect(tags.first?.objectName == "def456")
    }
}
