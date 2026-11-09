import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct PartialsBranchesPopupViewModelTests {
    private func branchNames(_ fixture: GitMergeFixture) async throws -> [String] {
        try await fixture.run("branch", "--format=%(refname:short)")
            .split(separator: "\n")
            .map(String.init)
            .sorted()
    }

    @Test
    func movingBackwardWithoutASelectionStartsAtTheLastSelectableRow() async throws {
        try await withTempDir { directory in
            let isolated = try makeIsolatedDefaults()
            defer { removeIsolatedDefaults(isolated.defaults, suiteName: isolated.suiteName) }
            let harness = try await BranchesPopupCoverageHarness.local(in: directory, defaults: isolated.defaults)
            let selectable = harness.model.rows.filter(\.isSelectable)

            harness.model.selectedID = nil
            harness.model.moveSelection(-1)
            #expect(harness.model.selectedID == selectable.last?.id)

            harness.model.selectedID = nil
            harness.model.moveSelection(1)
            #expect(harness.model.selectedID == selectable.first?.id)
        }
    }

    @Test
    func newBranchDialogSuggestsTheCurrentBranchUnlessHeadIsDetached() async throws {
        try await withTempDir { directory in
            let isolated = try makeIsolatedDefaults()
            defer { removeIsolatedDefaults(isolated.defaults, suiteName: isolated.suiteName) }
            let harness = try await BranchesPopupCoverageHarness.local(in: directory, defaults: isolated.defaults)
            var suggestions: [String] = []
            harness.model.dialogs.branchDialog = { request in
                suggestions.append(request.initialName)
                return nil
            }

            harness.model.promptNewBranch(from: nil)
            try await harness.fixture.run("checkout", "-q", "--detach", "main")
            try await harness.load()
            harness.model.promptNewBranch(from: nil)

            #expect(suggestions == ["main", ""])
            #expect(harness.model.currentBranchName == "HEAD")
        }
    }

    @Test
    func unmergedCommitsOfADeletedBranchAreListedAgainstDetachedHead() async throws {
        try await withTempDir { directory in
            let isolated = try makeIsolatedDefaults()
            defer { removeIsolatedDefaults(isolated.defaults, suiteName: isolated.suiteName) }
            let harness = try await BranchesPopupCoverageHarness.local(in: directory, defaults: isolated.defaults)
            try await harness.fixture.run("checkout", "-q", "--detach", "main")
            try await harness.load()
            var asked: [(name: String, commits: [String])] = []
            harness.model.dialogs.unmergedDelete = { name, commits in
                asked.append((name, commits))
                return .cancel
            }
            let feature = try harness.ref(.local, "feature")

            harness.model.delete(feature)
            try await harness.waitIdle()

            #expect(asked.map(\.name) == ["feature"])
            #expect(asked.first?.commits.count == 1)
            #expect(asked.first?.commits.first?.hasSuffix("feature work") == true)
            #expect(try await branchNames(harness.fixture).contains("feature"))
        }
    }

    @Test
    func forceDeleteIsStillOfferedWhenTheUnmergedCommitsCannotBeListed() async throws {
        try await withTempDir { directory in
            let isolated = try makeIsolatedDefaults()
            defer { removeIsolatedDefaults(isolated.defaults, suiteName: isolated.suiteName) }
            let harness = try await BranchesPopupCoverageHarness.local(in: directory, defaults: isolated.defaults)
            try await harness.fixture.run("update-ref", "refs/heads/-x", "main")
            try await harness.fixture.run("symbolic-ref", "HEAD", "refs/heads/-x")
            try await harness.load()
            #expect(harness.model.currentBranchName == "-x")
            var asked: [(name: String, commits: [String])] = []
            harness.model.dialogs.unmergedDelete = { name, commits in
                asked.append((name, commits))
                return .force
            }
            let feature = try harness.ref(.local, "feature")

            harness.model.delete(feature)
            try await harness.waitIdle()

            #expect(asked.map(\.name) == ["feature"])
            #expect(asked.first?.commits.isEmpty == true)
            #expect(try await branchNames(harness.fixture).contains("feature") == false)
        }
    }

    @Test
    func checkingOutARemoteBranchWhoseTrackingRefIsGoneChecksOutTheLocalBranch() async throws {
        try await withTempDir { directory in
            let isolated = try makeIsolatedDefaults()
            defer { removeIsolatedDefaults(isolated.defaults, suiteName: isolated.suiteName) }
            let harness = try await BranchesPopupCoverageHarness.cloned(in: directory, defaults: isolated.defaults)
            let origin = GitMergeFixture(existing: directory.appending(path: "origin"))
            try await origin.run("branch", "-D", "feature")
            try await harness.fixture.run("fetch", "-q", "--prune")
            await harness.manager.branchOpsRefresh()
            let remote = BranchesPopupRef(
                kind: .remote,
                name: "feature",
                shortName: "origin/feature",
                upstream: nil,
                isCurrent: false
            )

            harness.model.checkoutRemote(remote)
            try await harness.waitIdle()

            try await eventually { harness.manager.currentBranch?.name == "feature" }
            #expect(harness.dismissals == 1)
            #expect(harness.errors.isEmpty)
            #expect(harness.manager.lastAlert == nil)
        }
    }
}
