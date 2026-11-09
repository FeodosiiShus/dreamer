import AppKit
import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct GitCloneViewModelCoverage {
    private let recorder = GitCloneCoverageRecorder()

    private func makeModel(
        processRunner: any ProcessRunning = ProcessRunner(),
        gitClientRunner: (any ProcessRunning)? = nil
    ) -> GitCloneViewModel {
        GitCloneViewModel(services: recorder.services(processRunner: processRunner, gitClientRunner: gitClientRunner))
    }

    private func startCloning(_ model: GitCloneViewModel) {
        let recorder = recorder
        model.cloneRepository { recorder.cloned.append($0) }
    }

    private func clone(_ model: GitCloneViewModel) async {
        startCloning(model)
        await model.cloningTask?.value
    }

    @Test
    func defaultServicesAreLive() {
        let model = GitCloneViewModel()

        #expect(model.repoUrlStr.isEmpty)
        #expect(model.isCloning == false)
        #expect(model.cloningProgress.progress == 0)
        #expect(model.cloningProgress.state == .initialState)
        #expect(model.gitClient == nil)
        #expect(model.cloningTask == nil)
    }

    @Test
    func clipboardWithAValidUrlFillsTheField() {
        recorder.clipboard = "https://github.com/user/repo.git"
        let model = makeModel()

        model.checkClipboard()

        #expect(model.repoUrlStr == "https://github.com/user/repo.git")
    }

    @Test
    func clipboardWithoutAValidUrlLeavesTheFieldAlone() {
        let model = makeModel()
        model.repoUrlStr = "git@github.com:user/kept.git"

        recorder.clipboard = "just some text"
        model.checkClipboard()
        recorder.clipboard = nil
        model.checkClipboard()

        #expect(model.repoUrlStr == "git@github.com:user/kept.git")
    }

    @Test
    func gitIsInstalledWhenWhichSucceeds() async {
        #expect(await makeModel().isGitInstalled())
        #expect(await makeModel(processRunner: GitCloneCoverageRunner(which: .found)).isGitInstalled())
    }

    @Test
    func gitIsMissingWhenWhichFailsOrCannotLaunch() async {
        #expect(await makeModel(processRunner: GitCloneCoverageRunner(which: .missing)).isGitInstalled() == false)
        #expect(await makeModel(processRunner: GitCloneCoverageRunner(which: .launchFails)).isGitInstalled() == false)
    }

    @Test
    func missingGitShowsAnAlertAndNeverAsksForADestination() async {
        let model = makeModel(processRunner: GitCloneCoverageRunner(which: .missing))
        model.repoUrlStr = "https://github.com/user/repo.git"

        await clone(model)

        #expect(recorder.alerts == [
            .init(
                message: "Git installation not found.",
                info: "Ensure Git is installed on your system and try again.",
                buttons: ["OK"],
                style: .warning
            )
        ])
        #expect(recorder.panels.isEmpty)
        #expect(recorder.cloned.isEmpty)
        #expect(model.isCloning == false)
    }

    @Test
    func emptyUrlShowsAnAlert() async {
        let model = makeModel()

        await clone(model)

        #expect(recorder.alerts.map(\.message) == ["Url cannot be empty"])
        #expect(recorder.alerts.map(\.info) == ["You must specify a repository to clone"])
        #expect(recorder.panels.isEmpty)
    }

    @Test
    func unparsableUrlIsIgnoredSilently() async throws {
        let candidates = [
            "http://[::1", "https://[", "http://[abc", "https://[::", "http://[1:2:3:4:5:6:7:8:9]", "https://[g]"
        ]
        let unparsable = try #require(candidates.first(where: { URL(string: $0) == nil }))
        let model = makeModel()
        model.repoUrlStr = unparsable

        await clone(model)

        #expect(recorder.alerts.isEmpty)
        #expect(recorder.panels.isEmpty)
        #expect(model.gitClient == nil)
    }

    @Test
    func destinationPanelIsConfiguredAndNamedAfterTheRepositoryWithoutDotGit() async throws {
        let model = makeModel()
        model.repoUrlStr = "https://github.com/user/repo.git"
        await clone(model)
        model.repoUrlStr = "https://github.com/user/plain"
        await clone(model)

        #expect(recorder.panels.map(\.nameFieldStringValue) == ["repo", "plain"])
        let panel = try #require(recorder.panels.first)
        #expect(panel.prompt == "Clone")
        #expect(panel.nameFieldLabel == "Clone as")
        #expect(panel.title == "Clone a Repository")
        #expect(panel.showsHiddenFiles == false)
        #expect(panel.showsTagField == false)
        #expect(recorder.alerts.isEmpty)
        #expect(model.gitClient == nil)
        #expect(model.isCloning == false)
    }

    @Test
    func onlyATrailingDotGitIsStrippedFromTheSuggestedName() async {
        let model = makeModel()
        for name in ["foo.github.io", "foo.git", "foo.github.io.git", "foo.gitignore", "a.git.b"] {
            model.repoUrlStr = "https://example.com/user/\(name)"
            await clone(model)
        }

        #expect(recorder.panels.map(\.nameFieldStringValue) == [
            "foo.github.io", "foo", "foo.github.io", "foo.gitignore", "a.git.b"
        ])
    }

    @Test
    func existingDestinationShowsAnAlert() async throws {
        try await withTempDir { directory in
            recorder.destination = directory
            let model = makeModel()
            model.repoUrlStr = "https://github.com/user/repo.git"

            await clone(model)

            #expect(recorder.alerts.map(\.message) == ["Error"])
            #expect(recorder.alerts.map(\.info) == ["Directory already exists"])
            #expect(model.gitClient == nil)
            #expect(FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)))
        }
    }

    @Test
    func destinationBelowAFileShowsAFolderCreationAlert() async throws {
        try await withTempDir { directory in
            let blocker = directory.appending(path: "blocker")
            try Data("file".utf8).write(to: blocker)
            recorder.destination = blocker.appending(path: "child", directoryHint: .isDirectory)
            let model = makeModel()
            model.repoUrlStr = "https://github.com/user/repo.git"

            await clone(model)

            #expect(recorder.alerts.map(\.message) == ["Failed to create folder"])
            #expect(recorder.alerts.first?.info.isEmpty == false)
            #expect(model.gitClient == nil)
            #expect(recorder.cloned.isEmpty)
        }
    }

    @Test
    func clonesALocalBareRepository() async throws {
        try await withTempDir { directory in
            let origin = try await GitCloneCoverageOrigin.makeBare(in: directory, branches: ["feature"])
            let destination = directory.appending(path: "clone", directoryHint: .isDirectory)
            recorder.destination = destination
            let model = makeModel()
            model.repoUrlStr = origin.path(percentEncoded: false)

            await clone(model)

            #expect(recorder.alerts.isEmpty)
            #expect(recorder.cloned.map { $0.path(percentEncoded: false) } == [destination.path(percentEncoded: false)])
            #expect(FileManager.default.fileExists(atPath: destination.appending(path: "readme.txt").path))
            #expect(model.gitClient != nil)
            #expect(model.isCloning == false)
            #expect(recorder.panels.map(\.nameFieldStringValue) == ["origin"])
        }
    }

    @Test
    func failedRealCloneAlertsAndRemovesTheFolder() async throws {
        try await withTempDir { directory in
            let destination = directory.appending(path: "clone", directoryHint: .isDirectory)
            recorder.destination = destination
            let model = makeModel()
            model.repoUrlStr = directory.appending(path: "missing.git").path(percentEncoded: false)

            await clone(model)

            #expect(recorder.alerts.map(\.message) == ["Failed to clone"])
            #expect(recorder.alerts.first?.info.contains("does not exist") == true)
            #expect(FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) == false)
            #expect(recorder.cloned.isEmpty)
            #expect(model.isCloning == false)
        }
    }

    @Test
    func progressFollowsTheCloneOutputUntilCompletion() async throws {
        try await withTempDir { directory in
            let destination = directory.appending(path: "clone", directoryHint: .isDirectory)
            recorder.destination = destination
            let runner = GitCloneCoverageRunner(
                lines: [
                    "Cloning into 'clone'...",
                    "Counting objects: 100% (4/4), done.",
                    "Receiving objects:  50% (2/4)"
                ],
                ending: .exit(0)
            )
            let model = makeModel(processRunner: runner, gitClientRunner: runner)
            model.repoUrlStr = "https://github.com/user/repo.git"

            await clone(model)

            #expect(model.cloningProgress.state == .receiving)
            #expect(abs(model.cloningProgress.progress - 40) < 0.001)
            #expect(recorder.cloned.count == 1)
            #expect(recorder.alerts.isEmpty)
            #expect(model.isCloning == false)
            #expect(FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)))
        }
    }

    @Test
    func cancellingARunningCloneRemovesTheFolderWithoutCompleting() async throws {
        try await withTempDir { directory in
            let destination = directory.appending(path: "clone", directoryHint: .isDirectory)
            recorder.destination = destination
            let runner = GitCloneCoverageRunner(lines: ["Compressing objects: 100% (3/3)"], ending: .hold)
            let model = makeModel(processRunner: runner, gitClientRunner: runner)
            model.repoUrlStr = "https://github.com/user/repo.git"
            startCloning(model)
            let task = try #require(model.cloningTask)

            try await eventually { model.isCloning && model.cloningProgress.state == .compressing }
            #expect(abs(model.cloningProgress.progress - 20) < 0.001)
            model.cancelCloning()
            await task.value

            #expect(model.cloningTask == nil)
            #expect(model.isCloning == false)
            #expect(recorder.cloned.isEmpty)
            #expect(recorder.alerts.isEmpty)
            #expect(FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) == false)
        }
    }

    @Test
    func cancellingWhenTheFolderIsAlreadyGoneAlertsAboutTheDeletion() async throws {
        try await withTempDir { directory in
            let destination = directory.appending(path: "clone", directoryHint: .isDirectory)
            recorder.destination = destination
            let runner = GitCloneCoverageRunner(
                lines: ["Resolving deltas: 100% (1/1)"],
                ending: .hold,
                removesDestination: true
            )
            let model = makeModel(processRunner: runner, gitClientRunner: runner)
            model.repoUrlStr = "https://github.com/user/repo.git"
            startCloning(model)
            let task = try #require(model.cloningTask)

            try await eventually { model.isCloning && model.cloningProgress.state == .resolving }
            #expect(abs(model.cloningProgress.progress - 100) < 0.001)
            task.cancel()
            await task.value

            #expect(recorder.alerts.map(\.message) == ["Failed to delete folder"])
            #expect(recorder.alerts.first?.info.isEmpty == false)
            #expect(recorder.cloned.isEmpty)
        }
    }

    @Test
    func gitClientErrorsAreReportedWithTheirDescription() async throws {
        try await withTempDir { directory in
            let destination = directory.appending(path: "clone", directoryHint: .isDirectory)
            recorder.destination = destination
            let runner = GitCloneCoverageRunner(ending: .fail(GitClient.GitClientError.noRemoteConfigured))
            let model = makeModel(processRunner: runner, gitClientRunner: runner)
            model.repoUrlStr = "https://github.com/user/repo.git"

            await clone(model)

            #expect(recorder.alerts.map(\.message) == ["Failed to clone"])
            #expect(recorder.alerts.map(\.info) == ["No remote configured"])
            #expect(FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) == false)
            #expect(model.isCloning == false)
        }
    }

    @Test
    func otherErrorsAreReportedWithTheirLocalizedDescription() async throws {
        try await withTempDir { directory in
            let destination = directory.appending(path: "clone", directoryHint: .isDirectory)
            recorder.destination = destination
            let failure = ProcessRunnerError.timedOut(.seconds(1))
            let runner = GitCloneCoverageRunner(ending: .fail(failure))
            let model = makeModel(processRunner: runner, gitClientRunner: runner)
            model.repoUrlStr = "https://github.com/user/repo.git"

            await clone(model)

            #expect(recorder.alerts.map(\.message) == ["Failed to clone"])
            #expect(recorder.alerts.map(\.info) == [failure.localizedDescription])
            #expect(FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) == false)
            #expect(model.isCloning == false)
        }
    }

    @Test
    func cancelCloningWithoutATaskOnlyResetsTheFlag() {
        let model = makeModel()
        model.isCloning = true

        model.cancelCloning()

        #expect(model.isCloning == false)
        #expect(model.cloningTask == nil)
    }

    @Test
    func defaultServicesRouteAlertsAndDestinationPanelsThroughTheHeadlessModals() async {
        guard DreamderHeadless.isEnabled else { return }
        let model = GitCloneViewModel()

        model.cloneRepository { _ in }
        await model.cloningTask?.value
        model.repoUrlStr = "https://github.com/user/repo.git"
        model.cloneRepository { _ in }
        await model.cloningTask?.value

        #expect(DreamderHeadless.suppressedModals.contains("Url cannot be empty"))
        #expect(model.gitClient == nil)
        #expect(model.isCloning == false)
    }
}
