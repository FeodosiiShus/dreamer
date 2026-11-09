import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct SourceControlPullViewCoverageTests {
    private func config(
        _ handler: @escaping @Sendable (ProcessInvocation) throws -> ProcessOutput
    ) -> GitConfigClient {
        let runner = FakeProcessRunner(handler: handler)
        let commandRunner = GitCommandRunner(
            runner: runner,
            gitExecutable: URL(fileURLWithPath: "/usr/bin/git"),
            baseEnvironment: { [:] }
        )
        return GitConfigClient(commandRunner: commandRunner)
    }

    private func unsetConfig() -> GitConfigClient {
        config { _ in FakeProcessRunner.output("", exitCode: 1) }
    }

    @Test
    func idleStateRendersAndOptionsAndRunningStateChangeTheForm() async throws {
        try await withTempDir { directory in
            let repo = try await ScmViewsBRepository.make(in: directory, pushed: true)
            defer { repo.workspace.close() }
            let model = SourceControlPullModel(gitConfig: unsetConfig())
            let hosted = try repo.host { SourceControlPullView(model: model) }
            defer { hosted.close() }
            try await hosted.settle()
            await model.settingsLoad?.value

            #expect(hosted.renders())
            #expect(model.manager === repo.manager)
            #expect(repo.manager.operationRebase == false)
            #expect(ScmViewsCControls.switchStates(in: hosted) == [.off])

            repo.manager.operationRebase = true
            try await hosted.settle()
            #expect(ScmViewsCControls.switchStates(in: hosted) == [.on])
            let toggled = hosted.snapshot()

            model.loading = true
            try await hosted.settle()
            #expect(HostedView.pixelsDiffer(toggled, hosted.snapshot()))
        }
    }

    @Test
    func defaultInitializersReadTheGlobalPullSetting() async throws {
        try await withTempDir { directory in
            let repo = try await ScmViewsBRepository.make(in: directory, pushed: true)
            defer { repo.workspace.close() }
            let model = SourceControlPullModel()
            let hosted = try repo.host { SourceControlPullView(model: model) }
            defer { hosted.close() }
            try await hosted.settle()
            await model.settingsLoad?.value

            #expect(hosted.renders())

            let defaultHosted = try repo.host { SourceControlPullView() }
            defer { defaultHosted.close() }
            try await defaultHosted.settle()
            #expect(defaultHosted.renders())
        }
    }

    @Test
    func globalRebasePreferenceTurnsTheRebaseOptionOn() async throws {
        try await withTempDir { directory in
            let repo = try await ScmViewsBRepository.make(in: directory, pushed: true)
            defer { repo.workspace.close() }
            let model = SourceControlPullModel(gitConfig: config { _ in FakeProcessRunner.output("true\n") })
            let hosted = try repo.host { SourceControlPullView(model: model) }
            defer { hosted.close() }
            try await hosted.settle()
            await model.settingsLoad?.value

            #expect(repo.manager.operationRebase)
        }
    }

    @Test
    func globalPreferenceAgainstRebaseLeavesTheOptionOff() async throws {
        try await withTempDir { directory in
            let repo = try await ScmViewsBRepository.make(in: directory, pushed: true)
            defer { repo.workspace.close() }
            let model = SourceControlPullModel(gitConfig: config { _ in FakeProcessRunner.output("false\n") })
            let hosted = try repo.host { SourceControlPullView(model: model) }
            defer { hosted.close() }
            try await hosted.settle()
            await model.settingsLoad?.value

            #expect(repo.manager.operationRebase == false)
            #expect(repo.manager.lastAlert == nil)
        }
    }

    @Test
    func unreadablePullSettingsAreReported() async throws {
        try await withTempDir { directory in
            let repo = try await ScmViewsBRepository.make(in: directory, pushed: true)
            defer { repo.workspace.close() }
            let model = SourceControlPullModel(
                gitConfig: config { _ in FakeProcessRunner.output("", stderr: "fatal: bad config", exitCode: 2) }
            )
            let hosted = try repo.host { SourceControlPullView(model: model) }
            defer { hosted.close() }
            try await hosted.settle()
            await model.settingsLoad?.value

            #expect(repo.manager.lastAlert?.title == "Failed to read pull settings")
        }
    }

    @Test
    func submittingFastForwardsFromTheRemote() async throws {
        try await withTempDir { directory in
            let repo = try await ScmViewsBRepository.make(in: directory, pushed: true)
            defer { repo.workspace.close() }
            try await repo.commitOnRemoteFromAnotherClone(file: "remote.txt")
            try repo.selectOriginAndCurrentBranch()
            let model = SourceControlPullModel(gitConfig: unsetConfig())
            let hosted = try repo.host { SourceControlPullView(model: model) }
            defer { hosted.close() }
            try await hosted.settle()
            await model.settingsLoad?.value
            let dismissals = ScmViewsBCounter()
            model.dismiss = { dismissals.increment() }
            #expect(repo.fixture.exists("remote.txt") == false)

            model.submit()
            await model.submission?.value

            #expect(repo.fixture.exists("remote.txt"))
            #expect(model.loading == false)
            #expect(dismissals.value == 1)
            #expect(try await repo.headCommit() == repo.remoteHead())
        }
    }

    @Test
    func submittingWithRebaseReplaysLocalCommitsOntoTheRemote() async throws {
        try await withTempDir { directory in
            let repo = try await ScmViewsBRepository.make(in: directory, pushed: true)
            defer { repo.workspace.close() }
            try await repo.commitOnRemoteFromAnotherClone(file: "remote.txt")
            try repo.fixture.write("local.txt", "local\n")
            try await repo.fixture.commit("local")
            await repo.manager.branchOpsRefresh()
            #expect(repo.manager.changedFiles.isEmpty)
            try repo.selectOriginAndCurrentBranch()
            repo.manager.operationRebase = true
            let model = SourceControlPullModel(gitConfig: unsetConfig())
            let hosted = try repo.host { SourceControlPullView(model: model) }
            defer { hosted.close() }
            try await hosted.settle()
            await model.settingsLoad?.value
            let dismissals = ScmViewsBCounter()
            model.dismiss = { dismissals.increment() }

            await model.perform()

            #expect(repo.fixture.exists("remote.txt"))
            #expect(repo.fixture.exists("local.txt"))
            #expect(dismissals.value == 1)
            let merges = try await repo.fixture.run("rev-list", "--merges", "--count", "HEAD")
            #expect(merges.trimmingCharacters(in: .whitespacesAndNewlines) == "0")
        }
    }

    @Test
    func localChangesOpenTheStashSheetInsteadOfPulling() async throws {
        try await withTempDir { directory in
            let repo = try await ScmViewsBRepository.make(in: directory, pushed: true)
            defer { repo.workspace.close() }
            try await repo.commitOnRemoteFromAnotherClone(file: "remote.txt")
            try repo.fixture.write("a.txt", "changed\n")
            await repo.manager.refreshAllChangedFiles()
            try #require(repo.manager.changedFiles.isEmpty == false)
            try repo.selectOriginAndCurrentBranch()
            let model = SourceControlPullModel(gitConfig: unsetConfig())
            let dismissals = ScmViewsBCounter()
            model.attach(manager: repo.manager, dismiss: { dismissals.increment() })
            await model.settingsLoad?.value

            model.submit()
            await model.submission?.value

            #expect(repo.manager.stashSheetIsPresented)
            #expect(model.loading == false)
            #expect(dismissals.value == 0)
            #expect(repo.fixture.exists("remote.txt") == false)
        }
    }

    @Test
    func failingPullReportsTheErrorAndKeepsTheSheetOpen() async throws {
        try await withTempDir { directory in
            let repo = try await ScmViewsBRepository.make(in: directory, pushed: true)
            defer { repo.workspace.close() }
            try repo.selectOriginAndCurrentBranch()
            let model = SourceControlPullModel(gitConfig: unsetConfig())
            let hosted = try repo.host { SourceControlPullView(model: model) }
            defer { hosted.close() }
            try await hosted.settle()
            await model.settingsLoad?.value
            let dismissals = ScmViewsBCounter()
            model.dismiss = { dismissals.increment() }
            try repo.removeRemote()

            model.submit()
            await model.submission?.value

            #expect(model.loading == false)
            #expect(dismissals.value == 0)
            #expect(repo.manager.lastAlert?.title == "Failed to pull")
        }
    }

    @Test
    func cancelDismissesTheSheet() async throws {
        try await withTempDir { directory in
            let repo = try await ScmViewsBRepository.make(in: directory, pushed: true)
            defer { repo.workspace.close() }
            let model = SourceControlPullModel(gitConfig: unsetConfig())
            let hosted = try repo.host { SourceControlPullView(model: model) }
            defer { hosted.close() }
            try await hosted.settle()
            await model.settingsLoad?.value
            let dismissals = ScmViewsBCounter()
            model.dismiss = { dismissals.increment() }

            model.cancel()

            #expect(dismissals.value == 1)
        }
    }

    @Test
    func detachedModelIgnoresSubmitAndSettingsLoad() async {
        let model = SourceControlPullModel(gitConfig: unsetConfig())
        let dismissals = ScmViewsBCounter()
        model.dismiss = { dismissals.increment() }

        await model.perform()
        await model.loadPullSettings()

        #expect(model.loading == false)
        #expect(dismissals.value == 0)
    }
}
