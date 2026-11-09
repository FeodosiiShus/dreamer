import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct SourceControlNewBranchViewCoverageTests {
    private let remoteBranch = GitBranch(
        name: "origin/main",
        longName: "refs/remotes/origin/main",
        upstream: nil,
        ahead: 0,
        behind: 0
    )

    @Test
    func rendersFromTheCurrentBranchWithTheDefaultModel() async throws {
        try await withTempDir { directory in
            let repo = try await ScmViewsBRepository.make(in: directory, pushed: true)
            defer { repo.workspace.close() }
            let hosted = try repo.host { SourceControlNewBranchView(fromBranch: .constant(nil)) }
            defer { hosted.close() }
            try await hosted.settle()

            #expect(hosted.renders())
        }
    }

    @Test
    func nameChangesAreReflectedInTheForm() async throws {
        try await withTempDir { directory in
            let repo = try await ScmViewsBRepository.make(in: directory, pushed: true)
            defer { repo.workspace.close() }
            let model = SourceControlNewBranchModel(fromBranch: .constant(nil))
            let hosted = try repo.host { SourceControlNewBranchView(fromBranch: .constant(nil), model: model) }
            defer { hosted.close() }
            try await hosted.settle()
            let empty = hosted.snapshot()

            #expect(model.manager === repo.manager)
            model.name = "feature-x"
            try await hosted.settle()

            #expect(HostedView.pixelsDiffer(empty, hosted.snapshot()))
        }
    }

    @Test
    func remoteSourceBranchIsShownWithoutTheRefsPrefix() async throws {
        try await withTempDir { directory in
            let repo = try await ScmViewsBRepository.make(in: directory, pushed: true)
            defer { repo.workspace.close() }
            let local = try #require(repo.manager.currentBranch)
            let localHosted = try repo.host { SourceControlNewBranchView(fromBranch: .constant(local)) }
            defer { localHosted.close() }
            try await localHosted.settle()
            let localSnapshot = localHosted.snapshot()

            let remoteHosted = try repo.host { SourceControlNewBranchView(fromBranch: .constant(remoteBranch)) }
            defer { remoteHosted.close() }
            try await remoteHosted.settle()

            #expect(localHosted.renders())
            #expect(remoteHosted.renders())
            #expect(HostedView.pixelsDiffer(localSnapshot, remoteHosted.snapshot()))
        }
    }

    @Test
    func withoutAnySourceBranchTheFormStaysEmpty() async throws {
        try await withTempDir { directory in
            let workspace = try HostedViewFixture.makeWorkspace(in: directory)
            defer { workspace.close() }
            let manager = try #require(workspace.sourceControlManager)
            let model = SourceControlNewBranchModel(fromBranch: .constant(nil))
            let hosted = try HostedViewFixture.hostInWorkspace(workspace) {
                SourceControlNewBranchView(fromBranch: .constant(nil), model: model)
            }
            defer { hosted.close() }
            try await hosted.settle()

            #expect(manager.currentBranch == nil)
            #expect(model.manager == nil)
        }
    }

    @Test
    func submittingCreatesAndChecksOutTheBranch() async throws {
        try await withTempDir { directory in
            let repo = try await ScmViewsBRepository.make(in: directory, pushed: true)
            defer { repo.workspace.close() }
            let model = SourceControlNewBranchModel(fromBranch: .constant(nil))
            let hosted = try repo.host { SourceControlNewBranchView(fromBranch: .constant(nil), model: model) }
            defer { hosted.close() }
            try await hosted.settle()
            let dismissals = ScmViewsBCounter()
            model.dismiss = { dismissals.increment() }
            model.name = "feature-x"

            model.submit()
            await model.submission?.value

            #expect(dismissals.value == 1)
            #expect(repo.manager.currentBranch?.name == "feature-x")
            let current = try await repo.fixture.run("rev-parse", "--abbrev-ref", "HEAD")
            #expect(current.trimmingCharacters(in: .whitespacesAndNewlines) == "feature-x")
        }
    }

    @Test
    func submittingFromAnExplicitBranchUsesThatBranch() async throws {
        try await withTempDir { directory in
            let repo = try await ScmViewsBRepository.make(in: directory, pushed: true)
            defer { repo.workspace.close() }
            try await repo.fixture.run("branch", "base")
            await repo.manager.branchOpsRefresh()
            let base = try #require(repo.manager.branches.first { $0.name == "base" })
            let model = SourceControlNewBranchModel(fromBranch: .constant(base))
            let hosted = try repo.host { SourceControlNewBranchView(fromBranch: .constant(base), model: model) }
            defer { hosted.close() }
            try await hosted.settle()
            model.name = "topic"

            await model.perform()

            #expect(repo.manager.currentBranch?.name == "topic")
        }
    }

    @Test
    func failingCreationReportsTheErrorAndKeepsTheSheetOpen() async throws {
        try await withTempDir { directory in
            let repo = try await ScmViewsBRepository.make(in: directory, pushed: true)
            defer { repo.workspace.close() }
            let model = SourceControlNewBranchModel(fromBranch: .constant(nil))
            let hosted = try repo.host { SourceControlNewBranchView(fromBranch: .constant(nil), model: model) }
            defer { hosted.close() }
            try await hosted.settle()
            let dismissals = ScmViewsBCounter()
            model.dismiss = { dismissals.increment() }
            model.name = "main"

            model.submit()
            await model.submission?.value

            #expect(dismissals.value == 0)
            #expect(repo.manager.lastAlert?.title == "Failed to create branch")
        }
    }

    @Test
    func cancelDismissesTheSheet() async throws {
        try await withTempDir { directory in
            let repo = try await ScmViewsBRepository.make(in: directory, pushed: true)
            defer { repo.workspace.close() }
            let model = SourceControlNewBranchModel(fromBranch: .constant(nil))
            let hosted = try repo.host { SourceControlNewBranchView(fromBranch: .constant(nil), model: model) }
            defer { hosted.close() }
            try await hosted.settle()
            let dismissals = ScmViewsBCounter()
            model.dismiss = { dismissals.increment() }

            model.cancel()

            #expect(dismissals.value == 1)
        }
    }

    @Test
    func modelWithoutManagerOrSourceBranchIgnoresSubmit() async throws {
        let detached = SourceControlNewBranchModel(fromBranch: .constant(nil))
        let dismissals = ScmViewsBCounter()
        detached.dismiss = { dismissals.increment() }
        detached.name = "orphan"
        await detached.perform()
        #expect(dismissals.value == 0)

        try await withTempDir { directory in
            let workspace = try HostedViewFixture.makeWorkspace(in: directory)
            defer { workspace.close() }
            let manager = try #require(workspace.sourceControlManager)
            let attached = SourceControlNewBranchModel(fromBranch: .constant(nil))
            attached.attach(manager: manager, dismiss: { dismissals.increment() })
            attached.name = "orphan"

            await attached.perform()

            #expect(dismissals.value == 0)
            #expect(manager.lastAlert == nil)
        }
    }
}
