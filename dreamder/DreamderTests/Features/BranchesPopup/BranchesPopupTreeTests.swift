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
    func recentIsNotCapped() {
        let locals = (1...8).map { local("branch\($0)") }
        let sections = BranchesPopupTreeBuilder.build(input(
            locals: locals,
            recent: (1...8).map { "branch\($0)" },
            current: "branch8"
        ))
        let recentSection = sections.first { $0.id == .recent }
        #expect(recentSection?.nodes.count == 8)
        #expect(recentSection?.nodes.first?.title == "branch1")
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
        #expect(originGroup?.children.map(\.title) == ["master", "feature"])
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
        """
        let names = BranchesPopupReflogParser.recentBranchNames(from: output, limit: 10)
        #expect(names == ["feature", "fix/login"])
    }

    @Test
    func tagListParsesGitOutput() {
        let tags = GitTag.list(from: "v1.0|abc123\nv0.9|def456\n\n")
        #expect(tags.map(\.name) == ["v0.9", "v1.0"])
        #expect(tags.first?.objectName == "def456")
    }
}
