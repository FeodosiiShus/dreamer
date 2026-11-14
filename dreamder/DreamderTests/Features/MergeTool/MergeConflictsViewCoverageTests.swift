import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
private func mergeConflictsViewWorkspace(_ root: URL) -> WorkspaceDocument {
    let document = WorkspaceDocument()
    document.sourceControlManager = SourceControlManager(workspaceURL: root, editorManager: EditorManager())
    return document
}

@MainActor
private func mergeConflictsViewModel(_ root: URL, count: Int) async throws -> MergeConflictsViewModel {
    let model = try #require(MergeConflictsViewModel(workspace: mergeConflictsViewWorkspace(root)))
    await model.reload()
    try await eventually { model.entries.count == count }
    return model
}

private func mergeConflictsViewWriteBinary(_ root: URL, _ relativePath: String, _ bytes: [UInt8]) throws {
    let url = root.appending(path: relativePath)
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try Data(bytes).write(to: url)
}

private func mergeConflictsViewMixedConflicts(in root: URL) async throws -> GitMergeFixture {
    let fixture = try await GitMergeFixture(root: root)
    try fixture.write("gone.txt", "keep\nsecond\n")
    try fixture.write("plain.txt", "x\ny\nz\n")
    try fixture.write("src/deep/text.txt", "a\nb\nc\n")
    try mergeConflictsViewWriteBinary(root, "assets/blob.dat", [0, 1, 2, 3, 4, 5])
    try await fixture.commit("base")
    try await fixture.run("checkout", "-q", "-b", "feature")
    try fixture.write("gone.txt", "keep\nfeature\n")
    try fixture.write("plain.txt", "x\nfeature\nz\n")
    try fixture.write("src/deep/text.txt", "a\nfeature\nc\n")
    try fixture.write("new.txt", "feature\n")
    try mergeConflictsViewWriteBinary(root, "assets/blob.dat", [0, 1, 2, 3, 9])
    try await fixture.commit("feature")
    try await fixture.run("checkout", "-q", "main")
    try await fixture.run("rm", "-q", "gone.txt")
    try fixture.write("plain.txt", "x\nmain\nz\n")
    try fixture.write("src/deep/text.txt", "a\nmain\nc\n")
    try fixture.write("new.txt", "main\n")
    try mergeConflictsViewWriteBinary(root, "assets/blob.dat", [0, 1, 2, 3, 8])
    try await fixture.commit("main")
    _ = try await fixture.runIgnoringFailure("merge", "feature")
    return fixture
}

@MainActor
@Suite(.uiGate)
struct MergeConflictsViewCoverageTests {
    private let configPath = "app/config.txt"
    private let notesPath = "docs/notes.txt"

    @Test
    func tableShowsEveryKindOfConflictAndRepaintsWhenTheSelectionMoves() async throws {
        try await withTempDir { dir in
            _ = try await mergeConflictsViewMixedConflicts(in: dir)
            let model = try await mergeConflictsViewModel(dir, count: 5)
            #expect(model.entries.map(\.path) == [
                "assets/blob.dat", "gone.txt", "new.txt", "plain.txt", "src/deep/text.txt"
            ])
            let gone = try #require(model.entries.first { $0.path == "gone.txt" })
            #expect(model.detail(for: gone, choice: .yours) == "Deleted")
            #expect(model.detail(for: gone, choice: .theirs) == "Modified")
            let added = try #require(model.entries.first { $0.path == "new.txt" })
            #expect(model.detail(for: added, choice: .yours) == "Added")
            #expect(model.detail(for: added, choice: .theirs) == "Added")

            let hosted = HostedViewFixture.host(size: NSSize(width: 900, height: 420)) {
                MergeConflictsView(model: model)
            }
            defer { hosted.close() }
            try await hosted.settle()
            #expect(hosted.renders())

            let first = hosted.snapshot()
            model.select("plain.txt")
            try await hosted.settle()
            let second = hosted.snapshot()
            #expect(HostedView.pixelsDiffer(first, second))

            model.select("assets/blob.dat", extending: true)
            try await hosted.settle()
            #expect(HostedView.pixelsDiffer(second, hosted.snapshot()))
        }
    }

    @Test
    func rebaseAndCherryPickConflictsRenderWithSwappedSides() async throws {
        try await withTempDir { dir in
            _ = try await GitMergeFixture.rebaseConflict(in: dir)
            let model = try await mergeConflictsViewModel(dir, count: 1)
            let hosted = HostedViewFixture.host(size: NSSize(width: 900, height: 420)) {
                MergeConflictsView(model: model)
            }
            defer { hosted.close() }
            try await hosted.settle()

            #expect(model.summary == "Rebasing branch feature onto main")
            #expect(model.yoursHeader == "Yours (feature)")
            #expect(hosted.renders())
        }
        try await withTempDir { dir in
            _ = try await GitMergeFixture.cherryPickConflict(in: dir)
            let model = try await mergeConflictsViewModel(dir, count: 1)
            let hosted = HostedViewFixture.host(size: NSSize(width: 900, height: 420)) {
                MergeConflictsView(model: model)
            }
            defer { hosted.close() }
            try await hosted.settle()

            #expect(hosted.renders())
        }
    }

    @Test
    func deleteModifyAndBothAddedConflictsRender() async throws {
        try await withTempDir { dir in
            _ = try await GitMergeFixture.deleteModifyConflict(in: dir)
            let model = try await mergeConflictsViewModel(dir, count: 1)
            let hosted = HostedViewFixture.host(size: NSSize(width: 900, height: 420)) {
                MergeConflictsView(model: model)
            }
            defer { hosted.close() }
            try await hosted.settle()

            #expect(hosted.renders())
        }
        try await withTempDir { dir in
            _ = try await GitMergeFixture.bothAddedConflict(in: dir)
            let model = try await mergeConflictsViewModel(dir, count: 1)
            let hosted = HostedViewFixture.host(size: NSSize(width: 900, height: 420)) {
                MergeConflictsView(model: model)
            }
            defer { hosted.close() }
            try await hosted.settle()

            #expect(hosted.renders())
        }
    }

    @Test
    func emptyStateAppearsOnceEverythingIsAccepted() async throws {
        try await withTempDir { dir in
            let fixture = try await GitMergeFixture.mergeConflict(in: dir)
            let model = try await mergeConflictsViewModel(dir, count: 2)
            let hosted = HostedViewFixture.host(size: NSSize(width: 900, height: 420)) {
                MergeConflictsView(model: model)
            }
            defer { hosted.close() }
            try await hosted.settle()
            let populated = hosted.snapshot()

            model.select(configPath)
            model.select(notesPath, extending: true)
            MergeConflictsView(model: model).acceptTheirs()
            try await eventually { model.entries.isEmpty }
            try await eventually { model.isBusy == false }
            try await hosted.settle()

            #expect(model.isEmpty)
            #expect(model.summary == "All conflicts have been resolved")
            #expect(try await fixture.unmergedPaths().isEmpty)
            #expect(hosted.renders())
            #expect(HostedView.pixelsDiffer(populated, hosted.snapshot()))
        }
    }

    @Test
    func repositoryWithoutConflictsRendersTheEmptyState() async throws {
        try await withTempDir { dir in
            let fixture = try await GitMergeFixture(root: dir)
            try fixture.write("a.txt", "a\n")
            try await fixture.commit("initial")
            let model = try #require(MergeConflictsViewModel(workspace: mergeConflictsViewWorkspace(dir)))
            await model.reload()
            let hosted = HostedViewFixture.host(size: NSSize(width: 900, height: 420)) {
                MergeConflictsView(model: model)
            }
            defer { hosted.close() }
            try await hosted.settle()

            #expect(model.isEmpty)
            #expect(model.canAccept == false)
            #expect(model.canMerge == false)
            #expect(hosted.renders())
        }
    }

    @Test
    func acceptYoursShowsTheBusyIndicatorWhileGitWorks() async throws {
        try await withTempDir { dir in
            let fixture = try await GitMergeFixture.mergeConflict(in: dir)
            try fixture.write(".git/hooks/post-checkout", "#!/bin/sh\n/bin/sleep 2\n")
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: dir.appending(path: ".git/hooks/post-checkout").path(percentEncoded: false)
            )
            let model = try await mergeConflictsViewModel(dir, count: 2)
            let hosted = HostedViewFixture.host(size: NSSize(width: 900, height: 420)) {
                MergeConflictsView(model: model)
            }
            defer { hosted.close() }
            try await hosted.settle()
            let idle = hosted.snapshot()

            MergeConflictsView(model: model).acceptYours()
            try await eventually { model.isBusy }
            try await hosted.settle()
            #expect(model.canAccept == false)
            #expect(model.canMerge == false)
            #expect(hosted.renders())
            #expect(HostedView.pixelsDiffer(idle, hosted.snapshot()))

            try await eventually { model.isBusy == false }
            try await eventually { model.entries.count == 1 }
            #expect(try await fixture.unmergedPaths() == [notesPath])
            #expect(model.errorMessage == nil)
        }
    }

    @Test
    func failingAcceptShowsTheErrorInTheFooter() async throws {
        try await withTempDir { dir in
            let fixture = try await GitMergeFixture.mergeConflict(in: dir)
            let model = try await mergeConflictsViewModel(dir, count: 2)
            let hosted = HostedViewFixture.host(size: NSSize(width: 900, height: 420)) {
                MergeConflictsView(model: model)
            }
            defer { hosted.close() }
            try await hosted.settle()
            let healthy = hosted.snapshot()

            try fixture.write(".git/index.lock", "")
            await model.accept(.yours)
            try await hosted.settle()

            let message = try #require(model.errorMessage)
            #expect(message.isEmpty == false)
            #expect(model.isBusy == false)
            #expect(model.entries.count == 2)
            #expect(HostedView.pixelsDiffer(healthy, hosted.snapshot()))
        }
    }

    @Test
    func rowSelectionFollowsTableModifiers() async throws {
        try await withTempDir { dir in
            _ = try await GitMergeFixture.mergeConflict(in: dir)
            let model = try await mergeConflictsViewModel(dir, count: 2)
            let firstEntry = try #require(model.entries.first { $0.path == configPath })
            let secondEntry = try #require(model.entries.first { $0.path == notesPath })
            let first = MergeConflictRowView(model: model, entry: firstEntry, sideColumnWidth: 190)
            let second = MergeConflictRowView(model: model, entry: secondEntry, sideColumnWidth: 190)

            #expect(first.isSelected)
            #expect(first.background == Islands.selection)
            #expect(second.isSelected == false)
            #expect(second.background == Color.clear)

            second.select(modifiers: [])
            #expect(model.selectedPaths == [notesPath])
            #expect(second.background == Islands.selection)

            first.select(modifiers: [.shift])
            #expect(model.selectedPaths == [configPath, notesPath])

            first.select(modifiers: [.command])
            #expect(model.selectedPaths == [notesPath])

            first.click()
            #expect(model.selectedPaths == [configPath])
            #expect(model.primaryEntry?.path == configPath)

            second.setHovering(true)
            second.setHovering(false)
        }
    }

    @Test
    func doubleClickingARowOpensTheMergeWindowForIt() async throws {
        try await withTempDir { dir in
            _ = try await GitMergeFixture.mergeConflict(in: dir)
            let model = try await mergeConflictsViewModel(dir, count: 2)
            let entry = try #require(model.entries.first { $0.path == notesPath })
            let row = MergeConflictRowView(model: model, entry: entry, sideColumnWidth: 190)

            row.openMerge()
            let window = MergeToolPresenter.revisionsWindow(for: model.workspace, path: notesPath)
            window?.close()

            #expect(model.primaryEntry?.path == notesPath)
            #expect(window != nil)
        }
    }

    @Test
    func closeButtonClosesTheKeyWindow() async throws {
        try await withTempDir { dir in
            _ = try await GitMergeFixture.mergeConflict(in: dir)
            let model = try await mergeConflictsViewModel(dir, count: 2)
            let hosted = HostedViewFixture.host(size: NSSize(width: 900, height: 420)) {
                MergeConflictsView(model: model)
            }
            defer { hosted.close() }
            hosted.window.styleMask.insert(.closable)
            hosted.window.makeKey()
            let isKey = NSApp.keyWindow === hosted.window

            MergeConflictsView(model: model).closeWindow()

            if isKey {
                #expect(hosted.window.isVisible == false)
            }
        }
    }
}
