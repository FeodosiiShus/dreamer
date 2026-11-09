import Foundation
import Testing
@testable import Dreamder

@Suite
struct GitLogArgumentsTests {
    private let defaultTail = ["--extended-regexp", "--regexp-ignore-case"]

    private let alice = GitLogUser(name: "Alice Smith", email: "alice@example.com")
    private let bob = GitLogUser(name: "Bob Jones", email: "bob@example.com")

    private func parameters(
        _ filters: GitLogFilterCollection = GitLogFilterCollection(),
        options: GitLogOptions = GitLogOptions(),
        maxCount: Int? = nil,
        existingBranches: [String] = [],
        userResolver: GitLogUserResolver = GitLogUserResolver(),
        headIsResolvable: Bool = true
    ) -> GitLogParameters? {
        GitLogArguments.parameters(
            filters: filters,
            options: options,
            maxCount: maxCount,
            existingBranches: existingBranches,
            userResolver: userResolver,
            headIsResolvable: headIsResolvable
        )
    }

    @Test
    func noFilterLogsEverything() {
        let result = parameters()
        #expect(result?.filterParameters == ["HEAD", "--branches", "--remotes", "--tags"] + defaultTail)
        #expect(result?.configParameters == [])
    }

    @Test
    func unresolvableHeadIsDroppedFromTheDefaultSelection() {
        #expect(parameters(headIsResolvable: false)?.filterParameters == ["--branches", "--remotes", "--tags"] + defaultTail)
    }

    @Test
    func maxCountIsAppendedWhenPositive() {
        #expect(parameters(maxCount: 25)?.filterParameters.contains("--max-count=25") == true)
        #expect(parameters(maxCount: 0)?.filterParameters.contains { $0.hasPrefix("--max-count") } == false)
        #expect(parameters(maxCount: nil)?.filterParameters.contains { $0.hasPrefix("--max-count") } == false)
    }

    @Test
    func firstParentOptionAddsTheFlag() {
        var options = GitLogOptions()
        options.firstParent = true
        #expect(parameters(options: options)?.filterParameters.contains("--first-parent") == true)
        #expect(parameters()?.filterParameters.contains("--first-parent") == false)
    }

    @Test
    func plainTextUsesFixedStringsAndIgnoresCase() {
        let filters = GitLogFilterCollection(text: GitLogTextFilter.fromPattern("fix bug"))
        let tail = parameters(filters)?.filterParameters.suffix(3)
        #expect(Array(tail ?? []) == ["--grep=fix bug", "--fixed-strings", "--regexp-ignore-case"])
    }

    @Test
    func regexTextUsesExtendedRegexp() {
        let filters = GitLogFilterCollection(text: GitLogTextFilter.fromPattern("fix.*", isRegexpAllowed: true))
        let tail = parameters(filters)?.filterParameters.suffix(3)
        #expect(Array(tail ?? []) == ["--grep=fix.*", "--extended-regexp", "--regexp-ignore-case"])
    }

    @Test
    func matchCasePlainTextOmitsIgnoreCase() {
        let filters = GitLogFilterCollection(text: GitLogTextFilter.fromPattern("Fix", isMatchCase: true))
        let tail = parameters(filters)?.filterParameters.suffix(2)
        #expect(Array(tail ?? []) == ["--grep=Fix", "--fixed-strings"])
    }

    @Test
    func matchCaseRegexTextOmitsIgnoreCase() {
        let filters = GitLogFilterCollection(text: GitLogTextFilter.fromPattern("^Fix", isRegexpAllowed: true, isMatchCase: true))
        let tail = parameters(filters)?.filterParameters.suffix(2)
        #expect(Array(tail ?? []) == ["--grep=^Fix", "--extended-regexp"])
    }

    @Test
    func dateFilterUsesUnixTimestampsInUtc() {
        let filters = GitLogFilterCollection(
            date: GitLogDateFilter(
                after: Date(timeIntervalSince1970: 1_000.9),
                before: Date(timeIntervalSince1970: 2_000)
            )
        )
        let result = parameters(filters)?.filterParameters ?? []
        #expect(result == [
            "HEAD", "--branches", "--remotes", "--tags",
            "--after=1000 +0000", "--before=2000 +0000"
        ] + defaultTail)
    }

    @Test
    func afterOnlyDateFilterOmitsBefore() {
        let filters = GitLogFilterCollection(date: GitLogDateFilter(after: Date(timeIntervalSince1970: 5), before: nil))
        let result = parameters(filters)?.filterParameters ?? []
        #expect(result.contains("--after=5 +0000"))
        #expect(!result.contains { $0.hasPrefix("--before") })
    }

    @Test
    func gitDateFormatsSecondsAndZeroOffset() {
        #expect(GitLogArguments.gitDate(Date(timeIntervalSince1970: 1_700_000_000)) == "1700000000 +0000")
    }

    @Test
    func usersInRegexModeAreJoinedIntoOneAnchoredAlternation() {
        let resolver = GitLogUserResolver(allUsers: [alice, bob])
        let filters = GitLogFilterCollection(user: GitLogUserFilter(userNames: ["Alice Smith", "Bob Jones"]))
        let result = parameters(filters, userResolver: resolver)
        let expected = "--author=^Alice Smith <alice@example\\.com>$|^Bob Jones <bob@example\\.com>$"
        #expect(result?.filterParameters == ["HEAD", "--branches", "--remotes", "--tags"] + defaultTail + [expected])
        #expect(result?.configParameters == ["log.mailmap=false"])
    }

    @Test
    func usersInFixedStringsModeGetOneAuthorParameterEach() {
        let resolver = GitLogUserResolver(allUsers: [alice, bob])
        let filters = GitLogFilterCollection(
            user: GitLogUserFilter(userNames: ["Alice Smith", "Bob Jones"]),
            text: GitLogTextFilter.fromPattern("fix")
        )
        let result = parameters(filters, userResolver: resolver)?.filterParameters ?? []
        #expect(result.suffix(2) == ["--author=Alice Smith <alice@example.com>", "--author=Bob Jones <bob@example.com>"])
        #expect(result.contains("--fixed-strings"))
    }

    @Test
    func fixedStringsAuthorsDoubleBackslashes() {
        let user = GitLogUser(name: "Dom\\Ain User", email: "d@example.com")
        let resolver = GitLogUserResolver(allUsers: [user])
        let filters = GitLogFilterCollection(
            user: GitLogUserFilter(userNames: ["Dom\\Ain User"]),
            text: GitLogTextFilter.fromPattern("fix")
        )
        let result = parameters(filters, userResolver: resolver)?.filterParameters ?? []
        #expect(result.last == "--author=Dom\\\\Ain User <d@example.com>")
    }

    @Test
    func meResolvesToTheCurrentUser() {
        let resolver = GitLogUserResolver(currentUser: alice, allUsers: [alice, bob])
        let filters = GitLogFilterCollection(user: GitLogUserFilter(userNames: [GitLogUserFilter.me]))
        let result = parameters(filters, userResolver: resolver)?.filterParameters ?? []
        #expect(result.last == "--author=^Alice Smith <alice@example\\.com>$")
    }

    @Test
    func unresolvedUsersMakeTheLogImpossible() {
        let filters = GitLogFilterCollection(user: GitLogUserFilter(userNames: ["nobody"]))
        #expect(parameters(filters, userResolver: GitLogUserResolver(allUsers: [alice])) == nil)
    }

    @Test
    func noUserFilterAddsNoConfig() {
        let filters = GitLogFilterCollection(text: GitLogTextFilter.fromPattern("x"))
        #expect(parameters(filters)?.configParameters == [])
    }

    @Test
    func noMergesAddsMaxParents() {
        let result = parameters(GitLogFilterCollection(parent: .noMerges))?.filterParameters ?? []
        #expect(result.suffix(1) == ["--max-parents=1"])
        #expect(!result.contains { $0.hasPrefix("--min-parents") })
    }

    @Test
    func onlyMergesAddsMinParents() {
        let result = parameters(GitLogFilterCollection(parent: .onlyMerges))?.filterParameters ?? []
        #expect(result.suffix(1) == ["--min-parents=2"])
        #expect(!result.contains { $0.hasPrefix("--max-parents") })
    }

    @Test
    func bothParentBoundsAreEmittedMinFirst() {
        let filters = GitLogFilterCollection(parent: GitLogParentFilter(minParents: 2, maxParents: 3))
        #expect(Array((parameters(filters)?.filterParameters ?? []).suffix(2)) == ["--min-parents=2", "--max-parents=3"])
    }

    @Test
    func matchAllParentFilterAddsNothing() {
        let result = parameters(GitLogFilterCollection(parent: GitLogParentFilter()))?.filterParameters ?? []
        #expect(!result.contains { $0.contains("-parents") })
    }

    @Test
    func structureFilterGoesLastAfterSimplifyMerges() {
        var options = GitLogOptions()
        options.firstParent = true
        let filters = GitLogFilterCollection(
            text: GitLogTextFilter.fromPattern("fix"),
            structure: GitLogStructureFilter(paths: ["a.txt", "dir/b.txt"]),
            parent: .noMerges
        )
        let result = parameters(filters, options: options, maxCount: 10)?.filterParameters ?? []
        #expect(result.suffix(5) == ["--full-history", "--simplify-merges", "--", "a.txt", "dir/b.txt"])
        #expect(result.firstIndex(of: "--max-count=10") ?? Int.max < result.firstIndex(of: "--first-parent") ?? 0)
        #expect(result.firstIndex(of: "--first-parent") ?? Int.max < result.firstIndex(of: "--max-parents=1") ?? 0)
        #expect(result.firstIndex(of: "--max-parents=1") ?? Int.max < result.firstIndex(of: "--full-history") ?? 0)
    }

    @Test
    func emptyStructureFilterAddsNothing() {
        let result = parameters(GitLogFilterCollection(structure: GitLogStructureFilter(paths: [])))?.filterParameters ?? []
        #expect(!result.contains("--"))
        #expect(!result.contains("--full-history"))
    }

    @Test
    func branchFilterSelectsMatchingExistingBranches() {
        let filters = GitLogFilterCollection(branch: .fromBranch("main"))
        let result = parameters(filters, existingBranches: ["main", "dev"])
        #expect(result?.filterParameters == ["main"] + defaultTail)
    }

    @Test
    func branchFilterOfUnknownBranchMakesTheLogImpossible() {
        let filters = GitLogFilterCollection(branch: .fromBranch("ghost"))
        #expect(parameters(filters, existingBranches: ["main", "dev"]) == nil)
    }

    @Test
    func branchFilterAgainstNoBranchesIsImpossible() {
        #expect(parameters(GitLogFilterCollection(branch: .fromBranch("main")), existingBranches: []) == nil)
    }

    @Test
    func headIsSelectableByNameEvenWithoutBranches() {
        let filters = GitLogFilterCollection(branch: .fromBranch("HEAD"))
        #expect(parameters(filters, existingBranches: [])?.filterParameters == ["HEAD"] + defaultTail)
    }

    @Test
    func excludingBranchesKeepsOthersAndHead() {
        let filters = GitLogFilterCollection(branch: GitLogBranchFilter(excludedBranches: ["dev"]))
        let result = parameters(filters, existingBranches: ["main", "dev", "origin/main"])
        #expect(result?.filterParameters == ["main", "origin/main", "HEAD"] + defaultTail)
    }

    @Test
    func branchPatternsSelectMatchingBranches() {
        let filters = GitLogFilterCollection(branch: GitLogBranchFilter(patterns: ["release/.*"]))
        let result = parameters(filters, existingBranches: ["main", "release/1", "release/2"])
        #expect(result?.filterParameters == ["release/1", "release/2"] + defaultTail)
    }

    @Test
    func revisionFilterAddsItsHeads() {
        let filters = GitLogFilterCollection(revision: GitLogRevisionFilter(heads: ["abc123", "def456"]))
        #expect(parameters(filters)?.filterParameters == ["abc123", "def456"] + defaultTail)
    }

    @Test
    func emptyRevisionFilterMakesTheLogImpossible() {
        #expect(parameters(GitLogFilterCollection(revision: GitLogRevisionFilter(heads: []))) == nil)
    }

    @Test
    func rangeFilterBuildsDoubleDotRanges() {
        let filters = GitLogFilterCollection(
            range: GitLogRangeFilter(ranges: [
                GitLogRefRange(exclusiveRef: "main", inclusiveRef: "feature"),
                GitLogRefRange(exclusiveRef: "v1", inclusiveRef: "v2")
            ])
        )
        #expect(parameters(filters)?.filterParameters == ["main..feature", "v1..v2"] + defaultTail)
    }

    @Test
    func branchRevisionAndRangeAreCombinedInThatOrder() {
        let filters = GitLogFilterCollection(
            branch: .fromBranch("main"),
            range: GitLogRangeFilter(ranges: [GitLogRefRange(exclusiveRef: "a", inclusiveRef: "b")]),
            revision: GitLogRevisionFilter(heads: ["abc123"])
        )
        #expect(parameters(filters, existingBranches: ["main"])?.filterParameters == ["main", "abc123", "a..b"] + defaultTail)
    }

    @Test
    func headResolvabilityDoesNotAffectBranchFilters() {
        let filters = GitLogFilterCollection(branch: .fromBranch("main"))
        #expect(
            parameters(filters, existingBranches: ["main"], headIsResolvable: false)?.filterParameters
                == ["main"] + defaultTail
        )
    }

    @Test
    func argumentsPutConfigBeforeLogAndFilterParametersAfterFormat() {
        let parameters = GitLogParameters(
            configParameters: ["log.mailmap=false", "a=b"],
            filterParameters: ["HEAD", "--max-count=5"]
        )
        #expect(GitLogArguments.arguments(parameters: parameters, format: "%H") == [
            "-c", "log.mailmap=false", "-c", "a=b",
            "log", "--date-order", "-z", "--decorate=full", "--format=%H",
            "HEAD", "--max-count=5"
        ])
    }

    @Test
    func argumentsWithoutConfigStartWithLog() {
        let parameters = GitLogParameters(configParameters: [], filterParameters: ["HEAD"])
        #expect(GitLogArguments.arguments(parameters: parameters, format: GitClient.logGraphFormat).prefix(3) == ["log", "--date-order", "-z"])
    }
}

@Suite
struct GitLogBranchNamesTests {
    @Test
    func stripsHeadsAndRemotesPrefixes() {
        let output = "refs/heads/main\nrefs/heads/feature/x\nrefs/remotes/origin/main\n"
        #expect(GitClient.logGraphBranchNames(fromRefNames: output) == ["main", "feature/x", "origin/main"])
    }

    @Test
    func skipsTagsAndOtherNamespaces() {
        let output = "refs/tags/v1\nrefs/stash\nrefs/heads/main\n"
        #expect(GitClient.logGraphBranchNames(fromRefNames: output) == ["main"])
    }

    @Test
    func skipsHeadReferences() {
        let output = "refs/heads/HEAD\nrefs/remotes/origin/HEAD\nrefs/remotes/HEAD\nrefs/heads/main\n"
        #expect(GitClient.logGraphBranchNames(fromRefNames: output) == ["main"])
    }

    @Test
    func skipsEmptyNamesAndBlankLines() {
        let output = "\nrefs/heads/\nrefs/remotes/\n  refs/heads/dev  \n\n"
        #expect(GitClient.logGraphBranchNames(fromRefNames: output) == ["dev"])
    }

    @Test
    func emptyOutputHasNoBranches() {
        #expect(GitClient.logGraphBranchNames(fromRefNames: "").isEmpty)
    }
}
