import AppKit
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import Dreamder

@MainActor
private final class IslandsRefreshProbe {
    var managers: [SourceControlManager] = []
    var failure: (any Error)?
}

private struct IslandsProbeFailure: LocalizedError {
    var errorDescription: String? { "probe failed" }
}

@MainActor
@Suite(.uiGate)
struct IslandsWorkspaceSeamTests {
    private func makeRepositoryWorkspace(_ directory: URL) async throws -> WorkspaceDocument {
        let fixture = try await GitMergeFixture(root: directory)
        try fixture.write("a.txt", "a\n")
        try await fixture.commit("init")
        let workspace = try HostedViewFixture.makeWorkspace(in: directory)
        let editorManager = try #require(workspace.editorManager)
        workspace.sourceControlManager = SourceControlManager(workspaceURL: directory, editorManager: editorManager)
        return workspace
    }

    private func expectedProportion(delta: CGFloat, total: CGFloat) -> Double {
        let available = total - Islands.islandGap
        let current = available * 0.5
        let minimum = min(ToolWindowLayout.minSplitPart, available / 2)
        let moved = min(max(current + delta, minimum), available - minimum)
        return Double(moved / available)
    }

    @Test
    func resizeLeftAddsTheDragDeltaWithinTheClampedRange() {
        let manager = ToolWindowManager()

        manager.resizeLeft(by: 40, availableWidth: 1000)
        #expect(manager.leftWidth == 320)

        manager.resizeLeft(by: 5000, availableWidth: 1000)
        #expect(manager.leftWidth == ToolWindowLayout.maxLeftWidth)

        manager.resizeLeft(by: -5000, availableWidth: 1000)
        #expect(manager.leftWidth == ToolWindowLayout.minLeftWidth)

        manager.resizeLeft(by: 10, availableWidth: 400)
        #expect(manager.leftWidth == ToolWindowLayout.minLeftWidth)
    }

    @Test
    func resizeBottomSubtractsTheDragDeltaWithinTheClampedRange() {
        let manager = ToolWindowManager()

        manager.resizeBottom(by: 40, availableHeight: 800)
        #expect(manager.bottomHeight == 260)

        manager.resizeBottom(by: -5000, availableHeight: 800)
        #expect(manager.bottomHeight == 800 - ToolWindowLayout.minEditorHeight)

        manager.resizeBottom(by: 5000, availableHeight: 800)
        #expect(manager.bottomHeight == ToolWindowLayout.minBottomHeight)
    }

    @Test
    func movingTheLeftSplitDividerShiftsTheMainProportion() {
        let manager = ToolWindowManager()
        manager.setSplit(.structure, true)
        manager.show(.structure)

        manager.moveSplitDivider(on: .left, by: 100, total: 600)

        let expected = expectedProportion(delta: 100, total: 600)
        #expect(abs(manager.mainProportion(on: .left) - expected) < 1e-9)
        #expect(manager.mainProportion(on: .left) > ToolWindowSplitState.defaultSideWeight)
    }

    @Test
    func movingTheBottomSplitDividerBackShrinksTheMainProportion() {
        let manager = ToolWindowManager()
        manager.setSplit(.find, true)
        manager.show(.find)

        manager.moveSplitDivider(on: .bottom, by: -50, total: 800)

        let expected = expectedProportion(delta: -50, total: 800)
        #expect(abs(manager.mainProportion(on: .bottom) - expected) < 1e-9)
        #expect(manager.mainProportion(on: .bottom) < ToolWindowSplitState.defaultSideWeight)
    }

    @Test
    func movingTheDividerWithoutASplitPairKeepsTheFullProportion() {
        let manager = ToolWindowManager()

        manager.moveSplitDivider(on: .left, by: 100, total: 600)

        #expect(manager.mainProportion(on: .left) == 1)
    }

    @Test
    func adoptFocusActivatesOnlyADifferentEditor() {
        let manager = EditorManager()
        let original = manager.activeEditor
        let other = Editor()

        manager.adoptFocus(of: nil)
        #expect(manager.activeEditor == original)

        manager.adoptFocus(of: original)
        #expect(manager.activeEditor == original)

        manager.adoptFocus(of: other)
        #expect(manager.activeEditor == other)
    }

    @Test
    func adoptingAColorSchemeSwitchesTheThemeOnlyWhenAppearanceMatches() throws {
        try withTempDir { directory in
            let settings = Settings(baseURL: directory)
            let model = ThemeModel(
                baseURL: directory,
                bundledThemesURL: ThemeModel.defaultBundledThemesURL,
                preferencesStore: settings
            )
            let dark = try #require(model.selectedDarkTheme)
            let light = try #require(model.selectedLightTheme)
            #expect(dark != light)

            model.adopt(.dark, matchAppearance: true)
            #expect(model.colorScheme == .dark)
            #expect(model.selectedTheme == dark)

            model.adopt(.light, matchAppearance: true)
            #expect(model.colorScheme == .light)
            #expect(model.selectedTheme == light)

            model.adopt(.dark, matchAppearance: false)
            #expect(model.colorScheme == .dark)
            #expect(model.selectedTheme == light)
        }
    }

    @Test
    func recordWindowSizeStoresTheFrameOfTheClosingWindowOnly() throws {
        try withTempDir { directory in
            let workspace = try HostedViewFixture.makeWorkspace(in: directory)
            defer { workspace.close() }
            let window = NSWindow()
            let other = NSWindow()

            IslandsWorkspaceView.recordWindowSize(closing: other, window: window, in: workspace)
            IslandsWorkspaceView.recordWindowSize(closing: "not a window", window: window, in: workspace)
            IslandsWorkspaceView.recordWindowSize(closing: nil, window: window, in: workspace)
            IslandsWorkspaceView.recordWindowSize(closing: window, window: nil, in: workspace)
            #expect(workspace.getFromWorkspaceState(.workspaceWindowSize) == nil)

            IslandsWorkspaceView.recordWindowSize(closing: window, window: window, in: workspace)
            #expect(workspace.getFromWorkspaceState(.workspaceWindowSize) as? String == NSStringFromRect(window.frame))
        }
    }

    @Test
    func refreshGitDataRunsTheRefreshForAnEnabledWorkspace() async throws {
        try await withTempDir { directory in
            let workspace = try await makeRepositoryWorkspace(directory)
            defer { workspace.close() }
            let probe = IslandsRefreshProbe()

            await IslandsWorkspaceView.refreshGitData(enabled: true, in: workspace) { manager in
                probe.managers.append(manager)
            }

            #expect(probe.managers.count == 1)
            #expect(probe.managers.first === workspace.sourceControlManager)
            #expect(workspace.sourceControlManager?.lastAlert == nil)
        }
    }

    @Test
    func refreshGitDataDoesNothingWhenSourceControlIsDisabledOrMissing() async throws {
        try await withTempDir { directory in
            let workspace = try await makeRepositoryWorkspace(directory)
            defer { workspace.close() }
            let probe = IslandsRefreshProbe()

            await IslandsWorkspaceView.refreshGitData(enabled: false, in: workspace) { probe.managers.append($0) }
            workspace.sourceControlManager = nil
            await IslandsWorkspaceView.refreshGitData(enabled: true, in: workspace) { probe.managers.append($0) }

            #expect(probe.managers.isEmpty)
        }
    }

    @Test
    func refreshGitDataReportsFailuresThroughAnAlert() async throws {
        try await withTempDir { directory in
            let workspace = try await makeRepositoryWorkspace(directory)
            defer { workspace.close() }
            let probe = IslandsRefreshProbe()
            probe.failure = IslandsProbeFailure()

            await IslandsWorkspaceView.refreshGitData(enabled: true, in: workspace) { _ in
                if let failure = probe.failure {
                    throw failure
                }
            }

            #expect(
                workspace.sourceControlManager?.lastAlert
                    == SourceControlAlert(title: "Error refreshing Git data", message: "probe failed")
            )
        }
    }

    @Test
    func theDefaultRefreshLoadsRemotesAndStashesOfTheRepository() async throws {
        try await withTempDir { directory in
            let workspace = try await makeRepositoryWorkspace(directory)
            defer { workspace.close() }

            await IslandsWorkspaceView.refreshGitData(enabled: true, in: workspace)

            #expect(workspace.sourceControlManager?.remotes.isEmpty == true)
            #expect(workspace.sourceControlManager?.stashEntries.isEmpty == true)
            #expect(workspace.sourceControlManager?.lastAlert == nil)
        }
    }

    @Test
    func syncCurrentBranchRefreshesWhenEnabledAndClearsWhenDisabled() async throws {
        try await withTempDir { directory in
            let workspace = try await makeRepositoryWorkspace(directory)
            defer { workspace.close() }
            let manager = try #require(workspace.sourceControlManager)

            await IslandsWorkspaceView.syncCurrentBranch(true, in: workspace)
            #expect(manager.currentBranch?.name == "main")

            await IslandsWorkspaceView.syncCurrentBranch(false, in: workspace)
            #expect(manager.currentBranch == nil)
        }
    }

    @Test
    func syncCurrentBranchIgnoresWorkspacesWithoutSourceControl() async throws {
        try await withTempDir { directory in
            let workspace = try HostedViewFixture.makeWorkspace(in: directory)
            defer { workspace.close() }
            workspace.sourceControlManager = nil

            await IslandsWorkspaceView.syncCurrentBranch(true, in: workspace)
            await IslandsWorkspaceView.syncCurrentBranch(false, in: workspace)

            #expect(workspace.sourceControlManager == nil)
        }
    }

    @Test
    func droppedFileProvidersOpenTabsInTheActiveEditor() async throws {
        try await withTempDir { directory in
            let workspace = try HostedViewFixture.makeWorkspace(in: directory)
            defer { workspace.close() }
            let editorManager = try #require(workspace.editorManager)
            let fileURL = directory.appending(path: "dropped.txt")
            try "dropped".write(to: fileURL, atomically: true, encoding: .utf8)
            let provider = NSItemProvider()
            provider.registerDataRepresentation(
                forTypeIdentifier: UTType.fileURL.identifier,
                visibility: .all
            ) { completion in
                completion(fileURL.dataRepresentation, nil)
                return nil
            }

            let handled = IslandsWorkspaceView.openDroppedFiles([provider], in: editorManager)

            #expect(handled)
            try await eventually(timeout: .seconds(10)) {
                editorManager.activeEditor.tabs.contains { $0.file.url.lastPathComponent == "dropped.txt" }
            }
        }
    }

    @Test
    func providersWithoutAFileURLOpenNothing() async throws {
        try await withTempDir { directory in
            let workspace = try HostedViewFixture.makeWorkspace(in: directory)
            defer { workspace.close() }
            let editorManager = try #require(workspace.editorManager)
            let before = editorManager.activeEditor.tabs.count
            let provider = NSItemProvider()
            provider.registerDataRepresentation(
                forTypeIdentifier: UTType.plainText.identifier,
                visibility: .all
            ) { completion in
                completion(Data("text".utf8), nil)
                return nil
            }

            let handled = IslandsWorkspaceView.openDroppedFiles([provider, NSItemProvider()], in: editorManager)
            try await Task.sleep(for: .milliseconds(200))

            #expect(handled)
            #expect(editorManager.activeEditor.tabs.count == before)
        }
    }

    @Test
    func noProvidersStillCountAsHandled() throws {
        try withTempDir { directory in
            let workspace = try HostedViewFixture.makeWorkspace(in: directory)
            defer { workspace.close() }
            let editorManager = try #require(workspace.editorManager)

            #expect(IslandsWorkspaceView.openDroppedFiles([], in: editorManager))
        }
    }
}
