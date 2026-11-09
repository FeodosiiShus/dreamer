import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
private final class MergeConflictBannerRecorder {
    var path: String?
    var action: (() -> Void)?
    var registrations = 0
    var shownPaths: [String] = []
    var shownWorkspaces: [WorkspaceDocument] = []
}

@MainActor
@Suite(.uiGate)
struct MergeConflictEditorBannerCoverageTests {
    private let configPath = "app/config.txt"

    private func workspace(_ root: URL) -> WorkspaceDocument {
        let document = WorkspaceDocument()
        document.sourceControlManager = SourceControlManager(workspaceURL: root, editorManager: EditorManager())
        return document
    }

    private func host(
        _ workspace: WorkspaceDocument,
        fileURL: URL,
        recorder: MergeConflictBannerRecorder
    ) -> HostedView {
        HostedViewFixture.host(size: NSSize(width: 700, height: 80)) {
            MergeConflictEditorBanner(
                fileURL: fileURL,
                registerAutomation: { path, action in
                    recorder.path = path
                    recorder.action = action
                    recorder.registrations += 1
                },
                showMergeRevisions: { workspace, path in
                    recorder.shownWorkspaces.append(workspace)
                    recorder.shownPaths.append(path)
                }
            )
            .environment(workspace)
        }
    }

    private func awaitLoadedConflicts(_ workspace: WorkspaceDocument, count: Int) async throws {
        let manager = try #require(workspace.sourceControlManager)
        try await eventually {
            MergeConflictsCenter.shared.entries(for: manager.workspaceURL).count == count
        }
    }

    @Test
    func conflictedFileShowsTheStripAndResolvesThroughTheRegisteredAction() async throws {
        try await withTempDir { dir in
            let fixture = try await GitMergeFixture.mergeConflict(in: dir)
            let document = workspace(dir)
            let recorder = MergeConflictBannerRecorder()
            let hosted = host(document, fileURL: dir.appending(path: configPath), recorder: recorder)
            defer { hosted.close() }

            try await eventually { recorder.path == configPath }
            try await hosted.settle()
            #expect(recorder.registrations >= 1)
            let action = try #require(recorder.action)

            action()
            #expect(recorder.shownPaths == [configPath])
            #expect(recorder.shownWorkspaces.first === document)

            try fixture.write(configPath, "resolved\n")
            try await fixture.run("add", configPath)
            let manager = try #require(document.sourceControlManager)
            await MergeConflictsCenter.shared.refresh(manager: manager)

            try await eventually { recorder.path == nil }
            #expect(recorder.action == nil)
        }
    }

    @Test
    func fileOutsideTheConflictListHasNoStrip() async throws {
        try await withTempDir { dir in
            let fixture = try await GitMergeFixture.mergeConflict(in: dir)
            try fixture.write("clean.txt", "clean\n")
            let document = workspace(dir)
            let recorder = MergeConflictBannerRecorder()
            let hosted = host(document, fileURL: dir.appending(path: "clean.txt"), recorder: recorder)
            defer { hosted.close() }

            try await awaitLoadedConflicts(document, count: 2)
            try await hosted.settle()

            #expect(recorder.path == nil)
            #expect(recorder.action == nil)
            #expect(recorder.registrations >= 1)
        }
    }

    @Test
    func conflictedFileMissingFromDiskHasNoStrip() async throws {
        try await withTempDir { dir in
            let fixture = try await GitMergeFixture.mergeConflict(in: dir)
            try FileManager.default.removeItem(at: dir.appending(path: configPath))
            #expect(fixture.exists(configPath) == false)
            let document = workspace(dir)
            let recorder = MergeConflictBannerRecorder()
            let hosted = host(document, fileURL: dir.appending(path: configPath), recorder: recorder)
            defer { hosted.close() }

            try await awaitLoadedConflicts(document, count: 2)
            try await hosted.settle()

            #expect(recorder.path == nil)
            #expect(recorder.action == nil)
        }
    }

    @Test
    func bothDeletedEntryHasNoStripEvenWhenTheFileExists() async throws {
        try await withTempDir { dir in
            let fixture = try await GitMergeFixture(root: dir)
            try fixture.write("orig.txt", "line1\nline2\nline3\nline4\nline5\n")
            try await fixture.commit("base")
            try await fixture.run("checkout", "-q", "-b", "feature")
            try await fixture.run("mv", "orig.txt", "b.txt")
            try await fixture.commit("feature renames")
            try await fixture.run("checkout", "-q", "main")
            try await fixture.run("mv", "orig.txt", "a.txt")
            try await fixture.commit("main renames")
            _ = try await fixture.runIgnoringFailure("merge", "feature")
            try fixture.write("orig.txt", "recreated\n")

            let document = workspace(dir)
            let deletedRecorder = MergeConflictBannerRecorder()
            let deletedHosted = host(document, fileURL: dir.appending(path: "orig.txt"), recorder: deletedRecorder)
            defer { deletedHosted.close() }
            let addedRecorder = MergeConflictBannerRecorder()
            let addedHosted = host(document, fileURL: dir.appending(path: "a.txt"), recorder: addedRecorder)
            defer { addedHosted.close() }

            try await awaitLoadedConflicts(document, count: 3)
            let manager = try #require(document.sourceControlManager)
            let entries = MergeConflictsCenter.shared.entries(for: manager.workspaceURL)
            #expect(entries.first { $0.path == "orig.txt" }?.isBothDeleted == true)

            try await eventually { addedRecorder.path == "a.txt" }
            try await deletedHosted.settle()
            #expect(deletedRecorder.path == nil)
            #expect(deletedRecorder.action == nil)
        }
    }

    @Test
    func repositoryRootAndForeignFilesHaveNoStrip() async throws {
        try await withTempDir { dir in
            _ = try await GitMergeFixture.mergeConflict(in: dir)
            let document = workspace(dir)
            let rootRecorder = MergeConflictBannerRecorder()
            let rootHosted = host(document, fileURL: dir, recorder: rootRecorder)
            defer { rootHosted.close() }
            let foreignRecorder = MergeConflictBannerRecorder()
            let foreignHosted = host(
                document,
                fileURL: URL(fileURLWithPath: "/private/tmp/dreamder-foreign-\(UUID().uuidString).txt"),
                recorder: foreignRecorder
            )
            defer { foreignHosted.close() }

            try await awaitLoadedConflicts(document, count: 2)
            try await rootHosted.settle()

            #expect(rootRecorder.path == nil)
            #expect(rootRecorder.action == nil)
            #expect(foreignRecorder.path == nil)
            #expect(foreignRecorder.action == nil)
        }
    }

    @Test
    func workspaceWithoutSourceControlHasNoStrip() async throws {
        let recorder = MergeConflictBannerRecorder()
        let hosted = host(
            WorkspaceDocument(),
            fileURL: URL(fileURLWithPath: "/private/tmp/dreamder-no-scm.txt"),
            recorder: recorder
        )
        defer { hosted.close() }

        try await hosted.settle()

        #expect(recorder.path == nil)
        #expect(recorder.action == nil)
        #expect(recorder.registrations >= 1)
    }

    @Test
    func stripRendersAndResolvesItsPath() async throws {
        let recorder = MergeConflictBannerRecorder()
        let document = WorkspaceDocument()
        let strip = MergeConflictBannerStrip(
            workspace: document,
            path: "src/main.swift",
            showMergeRevisions: { workspace, path in
                recorder.shownWorkspaces.append(workspace)
                recorder.shownPaths.append(path)
            }
        )
        let hosted = HostedViewFixture.host(size: NSSize(width: 700, height: 80)) { strip }
        defer { hosted.close() }
        try await hosted.settle()

        strip.resolve()

        #expect(recorder.shownPaths == ["src/main.swift"])
        #expect(recorder.shownWorkspaces.first === document)
        #expect(MergeConflictBannerStrip.height == 30)
    }

    @Test
    func bannerDefaultsRouteToTheAutomationAndPresenter() {
        let url = URL(fileURLWithPath: "/private/tmp/dreamder-default-banner.txt")
        let banner = MergeConflictEditorBanner(fileURL: url)

        #expect(banner.fileURL == url)
    }
}
