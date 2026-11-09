import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct SourceControlSwitchViewCoverageTests {
    private func host(
        _ harness: ScmViewsCHarness,
        branch: GitBranch,
        model: SourceControlSwitchModel = SourceControlSwitchModel()
    ) throws -> HostedView {
        try harness.host(SourceControlSwitchView(branch: branch, model: model), size: NSSize(width: 460, height: 220))
    }

    @Test
    func rendersTheConfirmationWithAndWithoutACurrentBranch() async throws {
        try await withTempDir { dir in
            let harness = try await ScmViewsCHarness.make(in: dir)
            defer { harness.close() }
            let feature = try harness.localBranch(named: "feature")
            let model = SourceControlSwitchModel()
            let hosted = try host(harness, branch: feature, model: model)
            defer { hosted.close() }
            try await hosted.settle()

            #expect(hosted.renders())
            #expect(model.manager === harness.manager)
            let withCurrent = hosted.snapshot()

            harness.manager.currentBranch = nil
            try await hosted.settle()

            #expect(hosted.renders())
            #expect(HostedView.pixelsDiffer(withCurrent, hosted.snapshot()))
        }
    }

    @Test
    func switchChecksOutTheBranchWhenTheTreeIsClean() async throws {
        try await withTempDir { dir in
            let harness = try await ScmViewsCHarness.make(in: dir)
            defer { harness.close() }
            let feature = try harness.localBranch(named: "feature")
            let model = SourceControlSwitchModel()
            let dismissals = ScmViewsBCounter()
            model.attach(manager: harness.manager, dismiss: { dismissals.increment() })

            model.submit(feature)
            await model.submission?.value

            #expect(harness.manager.currentBranch?.name == "feature")
            #expect(dismissals.value == 1)
            #expect(!harness.manager.stashSheetIsPresented)
            #expect(harness.manager.lastAlert == nil)
            let current = try await harness.fixture.run("branch", "--show-current")
            #expect(current.trimmingCharacters(in: .whitespacesAndNewlines) == "feature")
        }
    }

    @Test
    func switchOpensTheStashSheetWhenLocalChangesExist() async throws {
        try await withTempDir { dir in
            let harness = try await ScmViewsCHarness.make(in: dir)
            defer { harness.close() }
            try await harness.dirtyWorkingTree()
            let feature = try harness.localBranch(named: "feature")
            let model = SourceControlSwitchModel()
            let dismissals = ScmViewsBCounter()
            model.attach(manager: harness.manager, dismiss: { dismissals.increment() })

            await model.perform(feature)

            #expect(harness.manager.stashSheetIsPresented)
            #expect(harness.manager.currentBranch?.name == "main")
            #expect(dismissals.value == 0)
            #expect(harness.manager.lastAlert == nil)
        }
    }

    @Test
    func switchingToAMissingBranchReportsAFailureAlert() async throws {
        try await withTempDir { dir in
            let harness = try await ScmViewsCHarness.make(in: dir)
            defer { harness.close() }
            let ghost = GitBranch(name: "ghost", longName: "refs/heads/ghost", upstream: nil, ahead: 0, behind: 0)
            let model = SourceControlSwitchModel()
            let dismissals = ScmViewsBCounter()
            model.attach(manager: harness.manager, dismiss: { dismissals.increment() })

            await model.perform(ghost)

            #expect(harness.manager.lastAlert?.title == "Failed to checkout")
            #expect(harness.manager.currentBranch?.name == "main")
            #expect(dismissals.value == 0)
        }
    }

    @Test
    func cancelDismissesWithoutSwitching() async throws {
        try await withTempDir { dir in
            let harness = try await ScmViewsCHarness.make(in: dir)
            defer { harness.close() }
            let feature = try harness.localBranch(named: "feature")
            let model = SourceControlSwitchModel()
            let hosted = try host(harness, branch: feature, model: model)
            defer { hosted.close() }
            try await hosted.settle()
            let dismissals = ScmViewsBCounter()
            model.dismiss = { dismissals.increment() }

            model.cancel()

            #expect(dismissals.value == 1)
            #expect(harness.manager.currentBranch?.name == "main")
            #expect(!harness.manager.stashSheetIsPresented)
            #expect(harness.manager.lastAlert == nil)
        }
    }

    @Test
    func detachedModelIgnoresSubmit() async {
        let model = SourceControlSwitchModel()
        let dismissals = ScmViewsBCounter()
        model.dismiss = { dismissals.increment() }
        let branch = GitBranch(name: "feature", longName: "refs/heads/feature", upstream: nil, ahead: 0, behind: 0)

        await model.perform(branch)

        #expect(dismissals.value == 0)
    }

    @Test
    func switchButtonActionSubmitsTheBranchOfTheView() async throws {
        try await withTempDir { dir in
            let harness = try await ScmViewsCHarness.make(in: dir)
            defer { harness.close() }
            let feature = try harness.localBranch(named: "feature")
            let model = SourceControlSwitchModel()
            let dismissals = ScmViewsBCounter()
            model.attach(manager: harness.manager, dismiss: { dismissals.increment() })
            let view = SourceControlSwitchView(branch: feature, model: model)

            view.submit()
            await model.submission?.value

            #expect(harness.manager.currentBranch?.name == "feature")
            #expect(dismissals.value == 1)
        }
    }
}
