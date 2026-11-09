import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct SourceControlStashViewCoverageTests {
    private func stashListOutput(_ harness: ScmViewsCHarness) async throws -> String {
        try await harness.fixture.run("stash", "list")
    }

    private func host(_ harness: ScmViewsCHarness, model: SourceControlStashModel) throws -> HostedView {
        try harness.host(SourceControlStashView(model: model))
    }

    @Test
    func rendersThePlainPullAndSwitchVariants() async throws {
        try await withTempDir { dir in
            let harness = try await ScmViewsCHarness.make(in: dir)
            defer { harness.close() }
            let model = SourceControlStashModel()
            let hosted = try host(harness, model: model)
            defer { hosted.close() }
            try await hosted.settle()

            #expect(hosted.renders())
            #expect(model.manager === harness.manager)
            #expect(ScmViewsCControls.hasEditableField(in: hosted))
            #expect(ScmViewsCControls.switches(in: hosted).isEmpty)
            let plain = hosted.snapshot()

            harness.manager.pullSheetIsPresented = true
            try await hosted.settle()
            #expect(ScmViewsCControls.switches(in: hosted).count == 1)
            let pull = hosted.snapshot()
            #expect(HostedView.pixelsDiffer(plain, pull))

            harness.manager.pullSheetIsPresented = false
            harness.manager.switchToBranch = try harness.localBranch(named: "feature")
            try await hosted.settle()
            #expect(ScmViewsCControls.switches(in: hosted).count == 1)
            let switching = hosted.snapshot()
            #expect(HostedView.pixelsDiffer(plain, switching))
            #expect(HostedView.pixelsDiffer(pull, switching))

            harness.manager.pullSheetIsPresented = true
            try await hosted.settle()
            #expect(ScmViewsCControls.switches(in: hosted).count == 1)
            #expect(hosted.renders())
        }
    }

    @Test
    func applyToggleReflectsTheModelState() async throws {
        try await withTempDir { dir in
            let harness = try await ScmViewsCHarness.make(in: dir)
            defer { harness.close() }
            harness.manager.pullSheetIsPresented = true
            let model = SourceControlStashModel()
            let hosted = try host(harness, model: model)
            defer { hosted.close() }
            try await hosted.settle()
            #expect(ScmViewsCControls.switchStates(in: hosted) == [.off])

            model.applyStashAfterOperation = true
            try await eventually { ScmViewsCControls.switchStates(in: hosted) == [.on] }

            model.applyStashAfterOperation = false
            try await eventually { ScmViewsCControls.switchStates(in: hosted) == [.off] }
        }
    }

    @Test
    func stashButtonStashesTheTypedMessage() async throws {
        try await withTempDir { dir in
            let harness = try await ScmViewsCHarness.make(in: dir)
            defer { harness.close() }
            try await harness.dirtyWorkingTree()
            #expect(!harness.manager.changedFiles.isEmpty)
            let model = SourceControlStashModel()
            let hosted = try host(harness, model: model)
            defer { hosted.close() }
            try await hosted.settle()
            let dismissals = ScmViewsBCounter()
            model.dismiss = { dismissals.increment() }

            try ScmViewsCControls.type("wip message", in: hosted)
            try await hosted.settle()
            #expect(model.message == "wip message")
            model.submit()
            await model.submission?.value

            #expect(harness.manager.stashEntries.count == 1)
            #expect(harness.manager.stashEntries.first?.message.contains("wip message") == true)
            try await eventually { harness.manager.changedFiles.isEmpty }
            #expect(try await stashListOutput(harness).contains("wip message"))
            #expect(try harness.fixture.read("a.txt") == "base\n")
            #expect(model.message.isEmpty)
            #expect(dismissals.value == 1)
            #expect(harness.manager.lastAlert == nil)
        }
    }

    @Test
    func stashWithoutAMessageStillStashes() async throws {
        try await withTempDir { dir in
            let harness = try await ScmViewsCHarness.make(in: dir)
            defer { harness.close() }
            try await harness.dirtyWorkingTree()
            let model = SourceControlStashModel()
            let dismissals = ScmViewsBCounter()
            model.attach(manager: harness.manager, dismiss: { dismissals.increment() })

            await model.perform()

            #expect(harness.manager.stashEntries.count == 1)
            try await eventually { harness.manager.changedFiles.isEmpty }
            #expect(dismissals.value == 1)
            #expect(harness.manager.lastAlert == nil)
        }
    }

    @Test
    func cancelDiscardsTheDraftAndStashesNothing() async throws {
        try await withTempDir { dir in
            let harness = try await ScmViewsCHarness.make(in: dir)
            defer { harness.close() }
            try await harness.dirtyWorkingTree()
            let model = SourceControlStashModel()
            let hosted = try host(harness, model: model)
            defer { hosted.close() }
            try await hosted.settle()
            let dismissals = ScmViewsBCounter()
            model.dismiss = { dismissals.increment() }

            try ScmViewsCControls.type("draft", in: hosted)
            try await hosted.settle()
            #expect(model.message == "draft")
            model.cancel()
            try await hosted.settle()

            #expect(model.message.isEmpty)
            #expect(dismissals.value == 1)
            #expect(harness.manager.stashEntries.isEmpty)
            #expect(try await stashListOutput(harness).isEmpty)
            #expect(try harness.fixture.read("a.txt") == "changed\n")
        }
    }

    @Test
    func stashPullSwitchAndApplyRunInOrderAndResetTheOperationState() async throws {
        try await withTempDir { dir in
            let harness = try await ScmViewsCHarness.make(in: dir, withRemote: true)
            defer { harness.close() }
            try await harness.dirtyWorkingTree()
            let main = try harness.localBranch(named: "main")
            let feature = try harness.localBranch(named: "feature")
            let manager = harness.manager
            manager.pullSheetIsPresented = true
            manager.operationRemote = GitRemote(name: "origin", pushLocation: "", fetchLocation: "")
            manager.operationBranch = main
            manager.operationRebase = true
            manager.switchToBranch = feature
            let model = SourceControlStashModel()
            model.applyStashAfterOperation = true
            model.message = "carry over"
            let dismissals = ScmViewsBCounter()
            model.attach(manager: manager, dismiss: { dismissals.increment() })

            model.submit()
            await model.submission?.value

            #expect(manager.switchToBranch == nil)
            #expect(!manager.pullSheetIsPresented)
            #expect(manager.operationRemote == nil)
            #expect(manager.operationBranch == nil)
            #expect(manager.currentBranch?.name == "feature")
            #expect(manager.stashEntries.count == 1)
            #expect(try harness.fixture.read("a.txt") == "changed\n")
            #expect(dismissals.value == 1)
            #expect(manager.lastAlert == nil)
        }
    }

    @Test
    func switchOnlyStashesThenChecksOutWithoutApplying() async throws {
        try await withTempDir { dir in
            let harness = try await ScmViewsCHarness.make(in: dir)
            defer { harness.close() }
            try await harness.dirtyWorkingTree()
            let manager = harness.manager
            manager.switchToBranch = try harness.localBranch(named: "feature")
            let model = SourceControlStashModel()
            model.attach(manager: manager, dismiss: {})

            await model.perform()

            #expect(manager.switchToBranch == nil)
            #expect(manager.currentBranch?.name == "feature")
            #expect(manager.stashEntries.count == 1)
            #expect(try harness.fixture.read("a.txt") == "base\n")
            #expect(manager.lastAlert == nil)
        }
    }

    @Test
    func switchWithApplyRestoresTheStashedChangesOnTheTargetBranch() async throws {
        try await withTempDir { dir in
            let harness = try await ScmViewsCHarness.make(in: dir)
            defer { harness.close() }
            try await harness.dirtyWorkingTree()
            let manager = harness.manager
            manager.switchToBranch = try harness.localBranch(named: "feature")
            let model = SourceControlStashModel()
            model.applyStashAfterOperation = true
            let dismissals = ScmViewsBCounter()
            model.attach(manager: manager, dismiss: { dismissals.increment() })

            await model.perform()

            #expect(manager.switchToBranch == nil)
            #expect(manager.currentBranch?.name == "feature")
            #expect(try harness.fixture.read("a.txt") == "changed\n")
            #expect(dismissals.value == 1)
            #expect(manager.lastAlert == nil)
        }
    }

    @Test
    func applyingWhenNothingWasStashedReportsMissingStash() async throws {
        try await withTempDir { dir in
            let harness = try await ScmViewsCHarness.make(in: dir)
            defer { harness.close() }
            let manager = harness.manager
            #expect(manager.changedFiles.isEmpty)
            manager.switchToBranch = try harness.localBranch(named: "feature")
            let model = SourceControlStashModel()
            let dismissals = ScmViewsBCounter()
            model.attach(manager: manager, dismiss: { dismissals.increment() })
            model.applyStashAfterOperation = true

            await model.perform()

            #expect(manager.lastAlert?.title == "Failed to stash changes")
            #expect(manager.lastAlert?.message.contains("Could not find last stash") == true)
            #expect(manager.switchToBranch != nil)
            #expect(dismissals.value == 0)
        }
    }

    @Test
    func failingPullAfterTheStashReportsAnAlertAndKeepsTheSheetState() async throws {
        try await withTempDir { dir in
            let harness = try await ScmViewsCHarness.make(in: dir)
            defer { harness.close() }
            try await harness.dirtyWorkingTree()
            let manager = harness.manager
            manager.pullSheetIsPresented = true
            let model = SourceControlStashModel()
            let dismissals = ScmViewsBCounter()
            model.attach(manager: manager, dismiss: { dismissals.increment() })

            await model.perform()

            #expect(manager.lastAlert?.title == "Failed to stash changes")
            #expect(manager.pullSheetIsPresented)
            #expect(manager.stashEntries.count == 1)
            #expect(dismissals.value == 0)
        }
    }

    @Test
    func detachedModelIgnoresSubmit() async {
        let model = SourceControlStashModel()
        model.message = "keep"
        let dismissals = ScmViewsBCounter()
        model.dismiss = { dismissals.increment() }

        await model.perform()

        #expect(model.message == "keep")
        #expect(dismissals.value == 0)
    }
}
