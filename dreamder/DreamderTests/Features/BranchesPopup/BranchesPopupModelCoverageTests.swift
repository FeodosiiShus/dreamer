import Foundation
import Testing
@testable import Dreamder

@Suite
struct BranchesPopupModelCoverageTests {
    @Test
    func tagsAreIdentifiedByTheirName() {
        let tag = GitTag(name: "v1.0", objectName: "abc1234")

        #expect(tag.id == "v1.0")
        #expect(Set([tag, GitTag(name: "v1.0", objectName: "abc1234")]).count == 1)
    }

    @Test
    func enumerationsAreIdentifiedByTheirRawValues() {
        #expect(BranchesPopupActionID.allCases.map(\.id) == BranchesPopupActionID.allCases.map(\.rawValue))
        #expect(BranchesPopupOngoingAction.allCases.map(\.id) == BranchesPopupOngoingAction.allCases.map(\.rawValue))
        #expect(BranchesPopupSectionID.allCases.map(\.id) == BranchesPopupSectionID.allCases.map(\.rawValue))
        #expect(BranchesPopupRefAction.allCases.map(\.id) == BranchesPopupRefAction.allCases.map(\.rawValue))
        #expect(Set(BranchesPopupRefAction.allCases.map(\.id)).count == BranchesPopupRefAction.allCases.count)
    }

    @Test
    func treeInputDefaultsToNoFavoritesAndGroupedDirectories() {
        let input = BranchesPopupTreeInput(
            localBranches: [],
            remoteBranches: [],
            tags: [],
            recentNames: [],
            currentBranchName: nil,
            showsRecentBranches: false,
            showsTags: false,
            query: ""
        )

        #expect(input.favorites.isEmpty)
        #expect(input.groupsByDirectory)
        #expect(BranchesPopupTreeBuilder.build(input).isEmpty)
    }

    @Test
    func tagListSkipsNamelessEntriesAndDefaultsMissingObjectNames() {
        let tags = GitTag.list(from: "v2|bbb\n|orphan\n\nv1\n  v3|ccc  ")

        #expect(tags.map(\.name) == ["v1", "v2", "v3"])
        #expect(tags.map(\.objectName) == ["", "bbb", "ccc"])
    }

    @Test
    func onlyRemoteRefsSplitIntoRemoteAndBranch() {
        let remote = BranchesPopupRef(kind: .remote, name: "main", shortName: "origin/main", upstream: nil, isCurrent: false)
        let local = BranchesPopupRef(kind: .local, name: "origin/main", shortName: "origin/main", upstream: nil, isCurrent: false)
        let tag = BranchesPopupRef(kind: .tag, name: "v1", shortName: "v1", upstream: nil, isCurrent: false)

        #expect(remote.remoteAndBranch?.remote == "origin")
        #expect(remote.remoteAndBranch?.branch == "main")
        #expect(local.remoteAndBranch == nil)
        #expect(tag.remoteAndBranch == nil)
    }

    @Test
    func equallyRankedRefsKeepTheirInputOrder() {
        let ordering = BranchesPopupRefOrdering(favorites: [], groupsByDirectory: true)
        let first = BranchesPopupRef(kind: .local, name: "same", shortName: "same", upstream: nil, isCurrent: false, ahead: 1)
        let second = BranchesPopupRef(kind: .local, name: "same", shortName: "same", upstream: nil, isCurrent: false, ahead: 2)

        #expect(ordering.sorted([first, second]).map(\.ahead) == [1, 2])
        #expect(ordering.sorted([second, first]).map(\.ahead) == [2, 1])
    }

    @Test
    func duplicateLocalBranchNamesResolveToTheFirstOccurrence() {
        let first = GitBranch(name: "main", longName: "refs/heads/main", upstream: nil, ahead: 1, behind: 0)
        let second = GitBranch(name: "main", longName: "refs/heads/main", upstream: nil, ahead: 2, behind: 0)
        let input = BranchesPopupTreeInput(
            localBranches: [first, second],
            remoteBranches: [],
            tags: [],
            recentNames: ["main"],
            currentBranchName: nil,
            showsRecentBranches: true,
            showsTags: false,
            query: ""
        )

        let sections = BranchesPopupTreeBuilder.build(input)

        #expect(sections.first { $0.id == .recent }?.refs.map(\.ahead) == [1])
        #expect(sections.first { $0.id == .local }?.refs.map(\.ahead) == [1, 2])
    }

    @Test
    func namesWithoutPathComponentsProduceNoNode() {
        let input = BranchesPopupTreeInput(
            localBranches: [
                GitBranch(name: "/", longName: "refs/heads//", upstream: nil, ahead: 0, behind: 0),
                GitBranch(name: "main", longName: "refs/heads/main", upstream: nil, ahead: 0, behind: 0)
            ],
            remoteBranches: [],
            tags: [],
            recentNames: [],
            currentBranchName: nil,
            showsRecentBranches: false,
            showsTags: false,
            query: ""
        )

        let local = BranchesPopupTreeBuilder.build(input).first { $0.id == .local }

        #expect(local?.refs.map(\.name) == ["/", "main"])
        #expect(local?.nodes.map(\.title) == ["main"])
    }

    @Test
    func topMatchSkipsRefsTheQueryDoesNotMatch() throws {
        let matcher = try #require(BranchesPopupMatcher(query: "feat"))
        let unrelated = BranchesPopupRef(kind: .local, name: "main", shortName: "main", upstream: nil, isCurrent: false)
        let related = BranchesPopupRef(kind: .local, name: "feature", shortName: "feature", upstream: nil, isCurrent: false)

        #expect(BranchesPopupPreferredSelection.topMatch(in: [unrelated, related], matcher: matcher)?.name == "feature")
        #expect(BranchesPopupPreferredSelection.topMatch(in: [unrelated], matcher: matcher) == nil)
    }
}
