import Foundation
import Testing
@testable import Dreamder

@Suite
struct GitLogArgumentsRefSafetyTests {
    private let defaultTail = ["--extended-regexp", "--regexp-ignore-case"]

    private func parameters(
        _ filters: GitLogFilterCollection,
        existingBranches: [String] = []
    ) -> GitLogParameters? {
        GitLogArguments.parameters(filters: filters, maxCount: nil, existingBranches: existingBranches)
    }

    private func revisionFilters(_ heads: [String]) -> GitLogFilterCollection {
        GitLogFilterCollection(revision: GitLogRevisionFilter(heads: heads))
    }

    private func rangeFilters(from exclusive: String, to inclusive: String) -> GitLogFilterCollection {
        GitLogFilterCollection(
            range: GitLogRangeFilter(ranges: [GitLogRefRange(exclusiveRef: exclusive, inclusiveRef: inclusive)])
        )
    }

    @Test(arguments: RefOperations.hostileNames)
    func revisionsStartingWithADashMakeTheLogImpossible(name: String) {
        #expect(parameters(revisionFilters([name])) == nil)
        #expect(parameters(revisionFilters(["abc123", name])) == nil)
    }

    @Test(arguments: RefOperations.hostileNames)
    func rangeEndsStartingWithADashMakeTheLogImpossible(name: String) {
        #expect(parameters(rangeFilters(from: name, to: "main")) == nil)
        #expect(parameters(rangeFilters(from: "main", to: name)) == nil)
    }

    @Test(arguments: RefOperations.spacedNames)
    func namesWithSpacesStayOneArgumentAfterEndOfOptionsOnGit244OrNewer(name: String) {
        #expect(parameters(revisionFilters([name]))?.filterParameters == defaultTail + ["--end-of-options", name])
        #expect(
            parameters(rangeFilters(from: name, to: name))?.filterParameters
                == defaultTail + ["--end-of-options", "\(name)..\(name)"]
        )
    }

    @Test(arguments: RefOperations.hostileNames)
    func existingBranchesStartingWithADashAreNeverSelected(name: String) {
        let excluding = GitLogFilterCollection(branch: GitLogBranchFilter(excludedBranches: ["dev"]))
        #expect(
            parameters(excluding, existingBranches: [name, "main", "dev"])?.filterParameters
                == defaultTail + ["--end-of-options", "main", "HEAD"]
        )
        #expect(parameters(GitLogFilterCollection(branch: .fromBranch(name)), existingBranches: [name]) == nil)
    }

    @Test
    func revisionsComeAfterEveryOptionAndPathsAfterTheDoubleDash() {
        var filters = revisionFilters(["abc123"])
        filters.structure = GitLogStructureFilter(paths: ["a.txt", "-weird.txt"])

        let result = parameters(filters)?.filterParameters

        #expect(result == defaultTail + [
            "--full-history", "--simplify-merges", "--end-of-options", "abc123", "--", "a.txt", "-weird.txt"
        ])
    }

    @Test
    func theDefaultSelectionKeepsItsConstantsAheadOfTheOptions() {
        var filters = GitLogFilterCollection()
        filters.structure = GitLogStructureFilter(paths: ["-weird.txt"])

        let result = parameters(filters)?.filterParameters

        #expect(result == ["HEAD", "--branches", "--remotes", "--tags"] + defaultTail + [
            "--full-history", "--simplify-merges", "--", "-weird.txt"
        ])
    }

    @Test
    func theGraphLogPutsRevisionsAfterAllOptionsInTheGitArguments() async throws {
        let (client, fake) = ScmFakeGit.client { _ in ScmFakeGit.ok() }

        _ = try await client.logGraph(filters: revisionFilters(["my feature"]))

        #expect(fake.invocations.map(ScmFakeGit.arguments) == [[
            "log", "--date-order", "-z", "--decorate=full", "--format=\(GitClient.logGraphFormat)",
            "--extended-regexp", "--regexp-ignore-case", "--max-count=2000", "--end-of-options", "my feature"
        ]])
    }

    @Test(arguments: RefOperations.hostileNames)
    func theGraphLogRunsNothingForADashLedRevision(name: String) async throws {
        let (client, fake) = ScmFakeGit.client { _ in ScmFakeGit.ok() }

        let commits = try await client.logGraph(filters: revisionFilters([name]))

        #expect(commits.isEmpty)
        #expect(fake.invocations.isEmpty)
    }
}
