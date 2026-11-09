import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct SourceControlPushViewCoverageTests {
    @Test
    func idleStateRendersAndPickerFillsInTheRemote() async throws {
        try await withTempDir { directory in
            let repo = try await ScmViewsBRepository.make(in: directory, pushed: true)
            defer { repo.workspace.close() }
            let model = SourceControlPushModel()
            let hosted = try repo.host { SourceControlPushView(model: model) }
            defer { hosted.close() }
            try await hosted.settle()

            #expect(hosted.renders())
            #expect(model.manager === repo.manager)
            #expect(model.loading == false)
            try await eventually { repo.manager.operationRemote?.name == "origin" }
        }
    }

    @Test
    func defaultInitializerBuildsItsOwnModel() async throws {
        try await withTempDir { directory in
            let repo = try await ScmViewsBRepository.make(in: directory, pushed: true)
            defer { repo.workspace.close() }
            let hosted = try repo.host { SourceControlPushView() }
            defer { hosted.close() }
            try await hosted.settle()

            #expect(hosted.renders())
        }
    }

    @Test
    func optionTogglesAndRunningStateChangeTheRenderedForm() async throws {
        try await withTempDir { directory in
            let repo = try await ScmViewsBRepository.make(in: directory, pushed: true)
            defer { repo.workspace.close() }
            let model = SourceControlPushModel()
            let hosted = try repo.host { SourceControlPushView(model: model) }
            defer { hosted.close() }
            try await hosted.settle()
            #expect(ScmViewsCControls.switchStates(in: hosted) == [.off, .off])

            repo.manager.operationForce = true
            repo.manager.operationIncludeTags = true
            try await hosted.settle()
            #expect(ScmViewsCControls.switchStates(in: hosted) == [.on, .on])
            let toggled = hosted.snapshot()

            model.loading = true
            try await hosted.settle()
            let running = hosted.snapshot()
            #expect(HostedView.pixelsDiffer(toggled, running))
            #expect(hosted.renders())
        }
    }

    @Test
    func submittingPushesLocalCommitsWithForceAndTags() async throws {
        try await withTempDir { directory in
            let repo = try await ScmViewsBRepository.make(in: directory, pushed: true)
            defer { repo.workspace.close() }
            try repo.fixture.write("b.txt", "b\n")
            try await repo.fixture.commit("second")
            await repo.manager.branchOpsRefresh()
            try repo.selectOriginAndCurrentBranch()
            repo.manager.operationForce = true
            repo.manager.operationIncludeTags = true
            let model = SourceControlPushModel()
            let hosted = try repo.host { SourceControlPushView(model: model) }
            defer { hosted.close() }
            try await hosted.settle()
            let dismissals = ScmViewsBCounter()
            model.dismiss = { dismissals.increment() }

            model.submit()
            await model.submission?.value

            #expect(model.loading == false)
            #expect(dismissals.value == 1)
            #expect(try await repo.remoteHead() == repo.headCommit())
        }
    }

    @Test
    func submittingABranchWithoutUpstreamSetsTheUpstream() async throws {
        try await withTempDir { directory in
            let repo = try await ScmViewsBRepository.make(in: directory, pushed: false)
            defer { repo.workspace.close() }
            #expect(repo.manager.currentBranch?.upstream == nil)
            try repo.selectOriginAndCurrentBranch()
            let model = SourceControlPushModel()
            let hosted = try repo.host { SourceControlPushView(model: model) }
            defer { hosted.close() }
            try await hosted.settle()
            let dismissals = ScmViewsBCounter()
            model.dismiss = { dismissals.increment() }

            await model.perform()

            #expect(dismissals.value == 1)
            #expect(try await repo.remoteHead() == repo.headCommit())
            #expect(repo.manager.currentBranch?.upstream != nil)
        }
    }

    @Test
    func failingPushReportsTheErrorAndKeepsTheSheetOpen() async throws {
        try await withTempDir { directory in
            let repo = try await ScmViewsBRepository.make(in: directory, pushed: true)
            defer { repo.workspace.close() }
            try repo.selectOriginAndCurrentBranch()
            let model = SourceControlPushModel()
            let hosted = try repo.host { SourceControlPushView(model: model) }
            defer { hosted.close() }
            try await hosted.settle()
            let dismissals = ScmViewsBCounter()
            model.dismiss = { dismissals.increment() }
            try repo.removeRemote()

            model.submit()
            await model.submission?.value

            #expect(model.loading == false)
            #expect(dismissals.value == 0)
            #expect(repo.manager.lastAlert?.title == "Failed to push")
        }
    }

    @Test
    func cancelDismissesTheSheet() async throws {
        try await withTempDir { directory in
            let repo = try await ScmViewsBRepository.make(in: directory, pushed: true)
            defer { repo.workspace.close() }
            let model = SourceControlPushModel()
            let hosted = try repo.host { SourceControlPushView(model: model) }
            defer { hosted.close() }
            try await hosted.settle()
            let dismissals = ScmViewsBCounter()
            model.dismiss = { dismissals.increment() }

            model.cancel()

            #expect(dismissals.value == 1)
        }
    }

    @Test
    func detachedModelIgnoresSubmit() async {
        let model = SourceControlPushModel()
        let dismissals = ScmViewsBCounter()
        model.dismiss = { dismissals.increment() }

        await model.perform()

        #expect(model.loading == false)
        #expect(dismissals.value == 0)
    }
}
