import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct SourceControlViewsCoverageTests {
    private func withIsolatedSettings(_ body: (Dreamder.Settings) async throws -> Void) async throws {
        try await withTempDir { directory in
            let settings = Settings(baseURL: directory.appending(path: "settings", directoryHint: .isDirectory))
            try await body(settings)
        }
    }

    private func gitModel(home: URL, store: CovExtGitConfigStore) -> SourceControlGitModel {
        CovExtGitModelFixtures.model(home: home, store: store)
    }

    @Test
    func generalViewRendersEveryToggleAndPickerState() async throws {
        try await withIsolatedSettings { settings in
            let hosted = HostedViewFixture.host(size: NSSize(width: 700, height: 700)) {
                SettingsInjector { Form { SourceControlGeneralView() }.formStyle(.grouped) }
                    .environment(\.settingsStore, settings)
            }
            defer { hosted.close() }
            try await hosted.settle()
            #expect(hosted.renders())

            let binding = SettingsScope.$current.withValue(settings) { SourceControlGeneralView().$settings }
            var general = binding.wrappedValue
            general.refreshStatusLocally = false
            general.fetchRefreshServerStatus = false
            general.addRemoveAutomatically = false
            general.selectFilesToCommit = false
            binding.wrappedValue = general
            try await hosted.settle()

            let togglesOff = settings.preferences.sourceControl.general
            #expect(!togglesOff.refreshStatusLocally)
            #expect(!togglesOff.fetchRefreshServerStatus)
            #expect(!togglesOff.addRemoveAutomatically)
            #expect(!togglesOff.selectFilesToCommit)
            #expect(hosted.renders())

            general.showSourceControlChanges = false
            general.revisionComparisonLayout = .localRight
            general.controlNavigatorOrder = .sortByDate
            binding.wrappedValue = general
            try await hosted.settle()

            let pickersChanged = settings.preferences.sourceControl.general
            #expect(!pickersChanged.showSourceControlChanges)
            #expect(pickersChanged.revisionComparisonLayout == .localRight)
            #expect(pickersChanged.controlNavigatorOrder == .sortByDate)
            #expect(hosted.renders())
        }
    }

    @Test
    func settingsViewTogglesTheTabsWithTheSourceControlSwitch() async throws {
        try await withTempDir { home in
            try await withIsolatedSettings { settings in
                let view = SourceControlSettingsView(
                    gitView: SourceControlGitView(model: gitModel(home: home, store: CovExtGitConfigStore()))
                )
                let hosted = HostedViewFixture.host(size: NSSize(width: 800, height: 800)) {
                    view.environment(\.settingsStore, settings)
                }
                defer { hosted.close() }
                try await hosted.settle()
                #expect(hosted.renders())
                let enabled = hosted.snapshot()

                settings.preferences.sourceControl.general.sourceControlIsEnabled = false
                try await hosted.settle()

                #expect(HostedView.pixelsDiffer(enabled, hosted.snapshot()))
            }
        }
    }

    @Test
    func settingsViewShowsTheGitTabWithItsFields() async throws {
        try await withTempDir { home in
            try await withIsolatedSettings { settings in
                settings.preferences.sourceControl.general.sourceControlIsEnabled = true
                try CovExtGitModelFixtures.write("*.log\nbuild/\n", to: home.appending(path: "nested.ignore"))
                let store = CovExtGitConfigStore([
                    "user.name": "Ada",
                    "user.email": "ada@example.com",
                    "init.defaultBranch": "trunk",
                    "pull.rebase": "true",
                    "core.excludesfile": "~/nested.ignore"
                ])
                let model = gitModel(home: home, store: store)
                let hosted = HostedViewFixture.host(size: NSSize(width: 800, height: 2000)) {
                    SourceControlSettingsView(selectedTab: "git", gitView: SourceControlGitView(model: model))
                        .environment(\.settingsStore, settings)
                }
                defer { hosted.close() }

                try await hosted.settle()

                try await eventually(timeout: .seconds(20)) {
                    model.hasAppeared
                        && model.authorName == "Ada"
                        && model.resolvedGitIgnorePath == "~/nested.ignore"
                        && model.ignorePatterns.patterns.map(\.value) == ["*.log", "build/"]
                }
                try await hosted.settle()
                #expect(hosted.renders())
            }
        }
    }

    @Test
    func settingsViewFallsBackToTheGeneralTabForUnknownSelections() async throws {
        try await withTempDir { home in
            try await withIsolatedSettings { settings in
                let hosted = HostedViewFixture.host(size: NSSize(width: 800, height: 800)) {
                    SourceControlSettingsView(
                        selectedTab: "other",
                        gitView: SourceControlGitView(model: gitModel(home: home, store: CovExtGitConfigStore()))
                    )
                    .environment(\.settingsStore, settings)
                }
                defer { hosted.close() }

                try await hosted.settle()

                #expect(hosted.renders())
            }
        }
    }

    @Test
    func gitViewReRendersWhenTheMergeCommitSettingChanges() async throws {
        try await withTempDir { home in
            try await withIsolatedSettings { settings in
                let model = gitModel(home: home, store: CovExtGitConfigStore())
                let hosted = HostedViewFixture.host(size: NSSize(width: 800, height: 900)) {
                    SourceControlGitView(model: model).environment(\.settingsStore, settings)
                }
                defer { hosted.close() }
                try await hosted.settle()
                try await eventually { model.hasAppeared }
                let before = hosted.snapshot()

                settings.preferences.sourceControl.git.showMergeCommitsPerFileLog.toggle()
                model.authorName = "Edited"
                model.preferRebaseWhenPulling = true
                try await hosted.settle()

                #expect(HostedView.pixelsDiffer(before, hosted.snapshot()))
            }
        }
    }

    @Test
    func ignoredFilesListShowsLoadedPatternsAndTheEmptyMessage() async throws {
        try await withTempDir { home in
            let store = CovExtGitConfigStore(["core.excludesfile": "~/nested.ignore"])
            let model = CovExtGitModelFixtures.ignoreModel(home: home, store: store)
            let hosted = HostedViewFixture.host(size: NSSize(width: 600, height: 400)) {
                IgnoredFilesListView(model: model)
            }
            defer { hosted.close() }
            try await hosted.settle()
            try await eventually { model.loadingPatterns == false }
            let empty = hosted.snapshot()
            #expect(hosted.renders())

            try CovExtGitModelFixtures.write("*.log\nbuild/\n", to: home.appending(path: "nested.ignore"))
            await model.loadPatterns()
            try await hosted.settle()

            #expect(model.patterns.map(\.value) == ["*.log", "build/"])
            #expect(HostedView.pixelsDiffer(empty, hosted.snapshot()))
        }
    }

    @Test
    func ignoredFilesListReflectsAddedAndRemovedPatterns() async throws {
        try await withTempDir { home in
            try CovExtGitModelFixtures.write("*.log\n", to: home.appending(path: "nested.ignore"))
            let store = CovExtGitConfigStore(["core.excludesfile": "~/nested.ignore"])
            let model = CovExtGitModelFixtures.ignoreModel(home: home, store: store)
            let hosted = HostedViewFixture.host(size: NSSize(width: 600, height: 400)) {
                IgnoredFilesListView(model: model)
            }
            defer { hosted.close() }
            try await hosted.settle()
            try await eventually(timeout: .seconds(30)) { model.patterns.count == 1 }
            try await hosted.settle()
            let single = hosted.snapshot()

            model.addPattern()
            let blank = try #require(model.patterns.last)
            #expect(model.patterns.count == 2)
            #expect(blank.value.isEmpty)
            model.removePatterns([blank.id])
            #expect(model.patterns.count == 1)

            model.patterns.append(GlobPattern(value: "*.tmp"))
            try await eventually(timeout: .seconds(30)) {
                hosted.layout()
                return HostedView.pixelsDiffer(single, hosted.snapshot())
            }
            let added = hosted.snapshot()

            model.removePatterns(Set(model.patterns.map(\.id)))
            #expect(model.patterns.isEmpty)
            try await eventually(timeout: .seconds(30)) {
                hosted.layout()
                return HostedView.pixelsDiffer(added, hosted.snapshot())
            }
        }
    }

    @Test
    func defaultInitializersBuildWithoutSideEffects() {
        _ = IgnoredFilesListView()
        _ = SourceControlGitView()
        _ = SourceControlSettingsView()
    }
}
