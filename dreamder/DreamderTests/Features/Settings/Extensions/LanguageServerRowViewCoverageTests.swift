import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct LanguageServerRowViewCoverageTests {
    private func makeRow(
        _ item: RegistryItem,
        manager: RegistryManager,
        model: LanguageServerRowState = LanguageServerRowState(),
        recorder: CovExtGitRowRecorder = CovExtGitRowRecorder()
    ) -> LanguageServerRowView {
        LanguageServerRowView(
            package: item,
            registryManager: manager,
            model: model,
            onCancel: recorder.cancel,
            onInstall: recorder.install
        )
    }

    private func host<Content: View>(@ViewBuilder _ content: () -> Content) -> HostedView {
        HostedViewFixture.host(size: NSSize(width: 640, height: 160), content)
    }

    @Test
    func idleRowRendersTheTitleAndIcon() async throws {
        try await withTempDir { directory in
            let manager = CovExtGitRegistryFixtures.manager(in: directory)
            let row = makeRow(try CovExtGitRegistryFixtures.item(name: "alpha-ls"), manager: manager)
            let hosted = host { row }
            defer { hosted.close() }

            try await hosted.settle()

            #expect(hosted.renders())
        }
    }

    @Test
    func hoveringRevealsTheInstallButton() async throws {
        try await withTempDir { directory in
            let manager = CovExtGitRegistryFixtures.manager(in: directory)
            let model = LanguageServerRowState()
            let row = makeRow(try CovExtGitRegistryFixtures.item(name: "alpha-ls"), manager: manager, model: model)
            let hosted = host { row }
            defer { hosted.close() }
            try await hosted.settle()
            let idle = hosted.snapshot()

            model.setHovering(true)
            try await hosted.settle()

            #expect(model.isHovering)
            #expect(HostedView.pixelsDiffer(idle, hosted.snapshot()))
            model.setHovering(false)
            #expect(model.isHovering == false)
        }
    }

    @Test
    func showMoreExpandsTheDescriptionHomepageAndInstaller() async throws {
        try await withTempDir { directory in
            let manager = CovExtGitRegistryFixtures.manager(in: directory)
            let model = LanguageServerRowState(isHovering: true)
            let item = try CovExtGitRegistryFixtures.item(
                name: "alpha-ls",
                description: "First line\nsecond line of a long description"
            )
            let row = makeRow(item, manager: manager, model: model)
            let hosted = host { row }
            defer { hosted.close() }
            try await hosted.settle()
            let collapsed = hosted.snapshot()

            model.toggleShowMore()
            try await hosted.settle()

            #expect(model.showMore)
            #expect(HostedView.pixelsDiffer(collapsed, hosted.snapshot()))
            model.toggleShowMore()
            #expect(model.showMore == false)
        }
    }

    @Test
    func showMoreOmitsTheInstallerLineForUnknownSources() async throws {
        try await withTempDir { directory in
            let manager = CovExtGitRegistryFixtures.manager(in: directory)
            let model = LanguageServerRowState(isHovering: true, showMore: true)
            let item = try CovExtGitRegistryFixtures.item(name: "tool", sourceID: "pkg:unknown/tool")
            let row = makeRow(item, manager: manager, model: model)
            let hosted = host { row }
            defer { hosted.close() }

            try await hosted.settle()

            #expect(hosted.renders())
        }
    }

    @Test
    func installedRowShowsTheEnabledToggleAndRemoveButton() async throws {
        try await withTempDir { directory in
            let manager = CovExtGitRegistryFixtures.manager(in: directory)
            let name = CovExtGitRegistryFixtures.uniqueName()
            CovExtGitRegistryFixtures.register(name, in: manager)
            defer { manager.installedLanguageServers.removeValue(forKey: name) }
            let model = LanguageServerRowState()
            let row = makeRow(try CovExtGitRegistryFixtures.item(name: name), manager: manager, model: model)
            let hosted = host { row }
            defer { hosted.close() }
            try await hosted.settle()
            let enabledIdle = hosted.snapshot()

            model.setHovering(true)
            try await hosted.settle()
            let enabledHover = hosted.snapshot()
            model.isRemoving = true
            try await hosted.settle()

            #expect(HostedView.pixelsDiffer(enabledIdle, enabledHover))
            #expect(HostedView.pixelsDiffer(enabledHover, hosted.snapshot()))
        }
    }

    @Test
    func disabledServerRowIsDimmedAndTogglingPersistsTheFlag() async throws {
        try await withTempDir { directory in
            let manager = CovExtGitRegistryFixtures.manager(in: directory)
            let name = CovExtGitRegistryFixtures.uniqueName()
            CovExtGitRegistryFixtures.register(name, in: manager)
            defer { manager.installedLanguageServers.removeValue(forKey: name) }
            let row = makeRow(try CovExtGitRegistryFixtures.item(name: name), manager: manager)
            let hosted = host { row }
            defer { hosted.close() }
            try await hosted.settle()
            let enabled = hosted.snapshot()

            row.setEnabled(false)
            try await hosted.settle()

            #expect(manager.installedLanguageServers[name]?.isEnabled == false)
            #expect(HostedView.pixelsDiffer(enabled, hosted.snapshot()))
            row.setEnabled(true)
            #expect(manager.installedLanguageServers[name]?.isEnabled == true)
        }
    }

    @Test
    func runningInstallOfThePackageShowsTheStopButton() async throws {
        try await withTempDir { directory in
            let manager = CovExtGitRegistryFixtures.manager(in: directory)
            let item = try CovExtGitRegistryFixtures.item(name: "alpha-ls")
            let row = makeRow(item, manager: manager)
            let hosted = host { row }
            defer { hosted.close() }
            try await hosted.settle()
            let idle = hosted.snapshot()

            manager.runningInstall = PackageManagerInstallOperation(package: item, steps: [])
            try await hosted.settle()
            let installing = hosted.snapshot()
            manager.runningInstall = nil

            #expect(HostedView.pixelsDiffer(idle, installing))
        }
    }

    @Test
    func anotherRunningInstallLeavesTheRowIdleAndDisablesInstall() async throws {
        try await withTempDir { directory in
            let manager = CovExtGitRegistryFixtures.manager(in: directory)
            let other = try CovExtGitRegistryFixtures.item(name: "other-ls")
            manager.runningInstall = PackageManagerInstallOperation(package: other, steps: [])
            let model = LanguageServerRowState(isHovering: true)
            let row = makeRow(try CovExtGitRegistryFixtures.item(name: "alpha-ls"), manager: manager, model: model)
            let hosted = host { row }
            defer { hosted.close() }

            try await hosted.settle()

            #expect(hosted.renders())
            manager.runningInstall = nil
        }
    }

    @Test
    func retryRowInvokesTheInstallCallback() async throws {
        try await withTempDir { directory in
            let manager = CovExtGitRegistryFixtures.manager(in: directory)
            let recorder = CovExtGitRowRecorder()
            let row = makeRow(try CovExtGitRegistryFixtures.item(name: "alpha-ls"), manager: manager, recorder: recorder)
            let hosted = host { row.failedRow() }
            defer { hosted.close() }
            try await hosted.settle()

            row.install()

            try await eventually { recorder.installs == ["alpha-ls"] }
            #expect(hosted.renders())
        }
    }

    @Test
    func alertContentRendersEveryBuilder() async throws {
        try await withTempDir { directory in
            let manager = CovExtGitRegistryFixtures.manager(in: directory)
            let model = LanguageServerRowState()
            model.removalError = CovExtGitLocalizedFailure()
            let row = makeRow(try CovExtGitRegistryFixtures.item(name: "alpha-ls"), manager: manager, model: model)
            let hosted = host {
                VStack {
                    row.removalActions()
                    row.removalMessage()
                    row.removalFailedActions()
                    row.removalFailedMessage()
                    row.installationButton()
                    row.isInstallingRow()
                    row.isHoveringRow()
                    row.installedRow()
                    row.letterIcon()
                }
            }
            defer { hosted.close() }

            try await hosted.settle()

            #expect(hosted.renders())
            #expect(model.removalErrorMessage == "Cov extension failure description")
        }
    }

    @Test
    func alertsPresentWhenTheirFlagsAreSet() async throws {
        try await withTempDir { directory in
            let manager = CovExtGitRegistryFixtures.manager(in: directory)
            let model = LanguageServerRowState()
            let row = makeRow(try CovExtGitRegistryFixtures.item(name: "alpha-ls"), manager: manager, model: model)
            let hosted = host { row }
            defer { hosted.close() }
            try await hosted.settle()

            model.requestRemoval()
            try await hosted.settle()
            #expect(hosted.renders())

            model.removalError = CovExtGitFailure()
            model.showingRemovalError = true
            try await hosted.settle()
            #expect(model.removalError != nil)
        }
    }

    @Test
    func openingTheHomepageIsInterceptedAndInvalidUrlsAreIgnored() async throws {
        try withTempDir { directory in
            let manager = CovExtGitRegistryFixtures.manager(in: directory)
            let valid = makeRow(try CovExtGitRegistryFixtures.item(name: "alpha-ls"), manager: manager)
            let invalid = makeRow(
                try CovExtGitRegistryFixtures.item(name: "beta-ls", homepage: ""),
                manager: manager
            )
            let opensBefore = DreamderHeadless.suppressedExternalOpens.count

            valid.openHomepage()
            let opensAfterValid = DreamderHeadless.suppressedExternalOpens.count
            invalid.openHomepage()

            #expect(opensAfterValid > opensBefore)
            #expect(DreamderHeadless.suppressedExternalOpens.count == opensAfterValid)
        }
    }

    @Test
    func removingAnInstalledServerDeletesItsDirectoryAndRegistration() async throws {
        try await withTempDir { directory in
            let manager = CovExtGitRegistryFixtures.manager(in: directory)
            let name = CovExtGitRegistryFixtures.uniqueName()
            CovExtGitRegistryFixtures.register(name, in: manager)
            defer { manager.installedLanguageServers.removeValue(forKey: name) }
            let packageDirectory = manager.installPath.appending(path: name)
            try FileManager.default.createDirectory(at: packageDirectory, withIntermediateDirectories: true)
            let model = LanguageServerRowState()
            let row = makeRow(try CovExtGitRegistryFixtures.item(name: name), manager: manager, model: model)

            row.removeLanguageServer()

            #expect(model.isRemoving)
            try await eventually { model.isRemoving == false && manager.installedLanguageServers[name] == nil }
            #expect(FileManager.default.fileExists(atPath: packageDirectory.path) == false)
            #expect(model.showingRemovalError == false)
        }
    }

    @Test
    func removingAServerWithoutADirectoryJustForgetsIt() async throws {
        try await withTempDir { directory in
            let manager = CovExtGitRegistryFixtures.manager(in: directory)
            let name = CovExtGitRegistryFixtures.uniqueName()
            CovExtGitRegistryFixtures.register(name, in: manager)
            defer { manager.installedLanguageServers.removeValue(forKey: name) }
            let model = LanguageServerRowState()

            model.remove(packageName: name, using: manager)

            try await eventually { model.isRemoving == false && manager.installedLanguageServers[name] == nil }
            #expect(model.removalError == nil)
        }
    }

    @Test
    func failedRemovalReportsTheError() async throws {
        guard getuid() != 0 else { return }
        try await withTempDir { directory in
            let manager = CovExtGitRegistryFixtures.manager(in: directory)
            let name = CovExtGitRegistryFixtures.uniqueName()
            CovExtGitRegistryFixtures.register(name, in: manager)
            let packageDirectory = manager.installPath.appending(path: name)
            try FileManager.default.createDirectory(at: packageDirectory, withIntermediateDirectories: true)
            let lockedParent = manager.installPath.path
            try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: lockedParent)
            defer {
                try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: lockedParent)
                manager.installedLanguageServers.removeValue(forKey: name)
            }
            let model = LanguageServerRowState()

            model.remove(packageName: name, using: manager)

            try await eventually { model.showingRemovalError }
            #expect(model.isRemoving == false)
            #expect(model.removalError != nil)
            #expect(model.removalErrorMessage != "An unknown error occurred")
            #expect(manager.installedLanguageServers[name] != nil)
        }
    }

    @Test
    func unknownRemovalErrorUsesTheFallbackMessage() {
        let model = LanguageServerRowState()

        #expect(model.removalErrorMessage == "An unknown error occurred")
        #expect(model.showingRemovalConfirmation == false)
        model.requestRemoval()
        #expect(model.showingRemovalConfirmation)
    }

    @Test
    func rowsAreEqualWhenTheyShowTheSamePackage() async throws {
        try withTempDir { directory in
            let manager = CovExtGitRegistryFixtures.manager(in: directory)
            let first = makeRow(try CovExtGitRegistryFixtures.item(name: "alpha-ls"), manager: manager)
            let same = makeRow(
                try CovExtGitRegistryFixtures.item(name: "alpha-ls", description: "changed"),
                manager: manager
            )
            let other = makeRow(try CovExtGitRegistryFixtures.item(name: "beta-ls"), manager: manager)

            #expect(first == same)
            #expect(first != other)
        }
    }

    @Test
    func rowWithAnEmptySanitizedNameRendersAFallbackLetter() async throws {
        try await withTempDir { directory in
            let manager = CovExtGitRegistryFixtures.manager(in: directory)
            let item = try CovExtGitRegistryFixtures.item(name: "-")
            let row = makeRow(item, manager: manager)
            let hosted = host { row }
            defer { hosted.close() }

            try await hosted.settle()

            #expect(item.sanitizedName.isEmpty)
            #expect(hosted.renders())
        }
    }
}
