import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct GitLogDetailsPaneCoverage {
    @MainActor
    private struct Session {
        let workspace: WorkspaceDocument
        let manager: SourceControlManager
        let model: GitLogViewModel
        let hosted: HostedView
        let input: GitToolWindowCovInput

        func close() {
            hosted.close()
            workspace.close()
        }

        func commit(_ subject: String) throws -> GitLogCommit {
            try #require(model.commits.first { $0.subject == subject })
        }

        func select(_ subject: String) async throws {
            let target = try commit(subject)
            await model.select(hash: target.hash)
            try await hosted.settle(.milliseconds(150))
        }

        func fileRowPoint(_ index: Int) -> CGPoint {
            let height = Islands.listRowHeight
            return CGPoint(x: 120, y: 4 + height + CGFloat(index) * height + height / 2)
        }
    }

    private func makeSession(_ directory: URL, loaded: Bool = true) async throws -> Session {
        let workspace = try HostedViewFixture.makeWorkspace(in: directory)
        let manager = try #require(workspace.sourceControlManager)
        let model = GitLogViewModel()
        if loaded {
            await model.load(manager: manager)
        }
        let hosted = try HostedViewFixture.hostInWorkspace(workspace) {
            GitLogDetailsPane(viewModel: model)
        }
        let input = GitToolWindowCovInput(hosted: hosted)
        try await hosted.settle(.milliseconds(150))
        return Session(workspace: workspace, manager: manager, model: model, hosted: hosted, input: input)
    }

    private func diffWindows(containing text: String) -> [NSWindow] {
        NSApp.windows.filter { $0.windowController is DiffViewerWindowController && $0.title.contains(text) }
    }

    @Test
    func placeholderShowsUntilACommitIsSelected() async throws {
        try await withTempDir { directory in
            _ = try await GitToolWindowCovRepo.make(in: directory)
            let session = try await makeSession(directory, loaded: false)
            defer { session.close() }
            let placeholder = session.hosted.snapshot()
            #expect(session.model.selectedCommit == nil)
            #expect(session.hosted.renders())

            await session.model.load(manager: session.manager)
            try await session.hosted.settle(.milliseconds(150))
            let details = session.hosted.snapshot()
            #expect(session.model.selectedCommit != nil)
            #expect(HostedView.pixelsDiffer(placeholder, details))

            await session.model.select(hash: nil)
            try await session.hosted.settle(.milliseconds(150))
            #expect(HostedView.pixelsDiffer(details, session.hosted.snapshot()))
        }
    }

    @Test
    func fileCountTitleAndCommitShapesRenderDistinctly() async throws {
        try await withTempDir { directory in
            _ = try await GitToolWindowCovRepo.make(in: directory)
            let session = try await makeSession(directory)
            defer { session.close() }

            try await session.select("Empty marker")
            #expect(session.model.selectedFiles.isEmpty)
            let noFiles = session.hosted.snapshot()

            try await session.select("Main change")
            #expect(session.model.selectedFiles.count == 1)
            let oneFile = session.hosted.snapshot()

            try await session.select("Feature work")
            #expect(session.model.selectedFiles.count == 2)
            let twoFiles = session.hosted.snapshot()

            #expect(HostedView.pixelsDiffer(noFiles, oneFile))
            #expect(HostedView.pixelsDiffer(oneFile, twoFiles))
            #expect(HostedView.pixelsDiffer(noFiles, twoFiles))
        }
    }

    @Test
    func longMessageAndRefsRenderInTheDetailsSection() async throws {
        try await withTempDir { directory in
            _ = try await GitToolWindowCovRepo.make(in: directory)
            let session = try await makeSession(directory)
            defer { session.close() }

            try await session.select("Feature work")
            let feature = try session.commit("Feature work")
            #expect(feature.refs.isEmpty)
            #expect(session.model.selectedMessage.contains("Paragraph 12"))
            let withoutRefs = session.hosted.snapshot()
            #expect(session.hosted.renders())

            try await session.select("Empty marker")
            let marker = try session.commit("Empty marker")
            #expect(marker.refs.contains { $0.kind == .branch })
            let withBranchRef = session.hosted.snapshot()

            try await session.select("initial")
            let initial = try session.commit("initial")
            #expect(initial.refs.contains { $0.kind == .tag })

            try await session.select("Remove guide")
            let head = try session.commit("Remove guide")
            #expect(head.refs.contains { $0.kind == .head })

            #expect(HostedView.pixelsDiffer(withoutRefs, withBranchRef))
        }
    }

    @Test
    func mergeCommitListsTheChangesItBroughtIn() async throws {
        try await withTempDir { directory in
            _ = try await GitToolWindowCovRepo.make(in: directory)
            let session = try await makeSession(directory)
            defer { session.close() }

            try await session.select("Merge feature")

            let merge = try session.commit("Merge feature")
            #expect(merge.isMerge)
            #expect(session.model.selectedFiles.count == 2)
            #expect(session.hosted.renders())
        }
    }

    @Test
    func showDiffMenuItemOpensTheCommitDiffWindow() async throws {
        try await withTempDir { directory in
            _ = try await GitToolWindowCovRepo.make(in: directory)
            let session = try await makeSession(directory)
            defer { session.close() }
            try await session.select("Feature work")
            let shortHash = try session.commit("Feature work").shortHash
            try await eventually(timeout: .seconds(10)) { session.model.selectedFiles.count == 2 }
            #expect(diffWindows(containing: shortHash).isEmpty)

            let menu = try session.input.contextMenu(at: session.fileRowPoint(0))
            let index = try #require(menu.items.firstIndex { $0.title == "Show Diff" })
            menu.performActionForItem(at: index)

            try await eventually(timeout: .seconds(10)) { !diffWindows(containing: shortHash).isEmpty }
            let windows = diffWindows(containing: shortHash)
            #expect(windows.allSatisfy { $0.title.contains("feature.txt") })
            windows.forEach { $0.close() }
        }
    }

    @Test
    func rootCommitDiffHasNoParentSide() async throws {
        try await withTempDir { directory in
            _ = try await GitToolWindowCovRepo.make(in: directory)
            let session = try await makeSession(directory)
            defer { session.close() }
            try await session.select("initial")
            let shortHash = try session.commit("initial").shortHash

            let menu = try session.input.contextMenu(at: session.fileRowPoint(0))
            let index = try #require(menu.items.firstIndex { $0.title == "Show Diff" })
            menu.performActionForItem(at: index)

            try await eventually(timeout: .seconds(10)) { !diffWindows(containing: shortHash).isEmpty }
            let windows = diffWindows(containing: shortHash)
            #expect(windows.allSatisfy { $0.title.contains("Empty") })
            windows.forEach { $0.close() }
        }
    }

    @Test
    func openFileContextMenuOpensATemporaryEditorTab() async throws {
        try await withTempDir { directory in
            _ = try await GitToolWindowCovRepo.make(in: directory)
            let session = try await makeSession(directory)
            defer { session.close() }
            try await session.select("Feature work")
            let editorManager = try #require(session.workspace.editorManager)
            try await eventually(timeout: .seconds(10)) { session.model.selectedFiles.count == 2 }

            let menu = try session.input.contextMenu(at: session.fileRowPoint(0))
            let index = try #require(menu.items.firstIndex { $0.title == "Open File" })
            menu.performActionForItem(at: index)

            try await eventually(timeout: .seconds(10)) {
                editorManager.activeEditor.tabs.contains { $0.file.url.lastPathComponent == "feature.txt" }
            }
        }
    }

    @Test
    func openingADeletedFileDoesNothing() async throws {
        try await withTempDir { directory in
            _ = try await GitToolWindowCovRepo.make(in: directory)
            let session = try await makeSession(directory)
            defer { session.close() }
            try await session.select("Remove guide")
            let editorManager = try #require(session.workspace.editorManager)
            #expect(session.model.selectedFiles.first?.status == .deleted)

            let menu = try session.input.contextMenu(at: session.fileRowPoint(0))
            let index = try #require(menu.items.firstIndex { $0.title == "Open File" })
            menu.performActionForItem(at: index)
            try await Task.sleep(for: .milliseconds(300))

            #expect(editorManager.activeEditor.tabs.isEmpty)
        }
    }

    @Test
    func openingAFileOutsideTheWorkspaceFolderDoesNothing() async throws {
        try await withTempDir { directory in
            let fixture = try await GitMergeFixture(root: directory)
            try fixture.write("outside.txt", "outside\n")
            try fixture.write("sub/inside.txt", "inside\n")
            try await fixture.commit("both")
            let workspace = try HostedViewFixture.makeWorkspace(in: directory.appending(path: "sub"))
            defer { workspace.close() }
            let manager = try #require(workspace.sourceControlManager)
            let model = GitLogViewModel()
            await model.load(manager: manager)
            let hosted = try HostedViewFixture.hostInWorkspace(workspace) {
                GitLogDetailsPane(viewModel: model)
            }
            defer { hosted.close() }
            let input = GitToolWindowCovInput(hosted: hosted)
            try await hosted.settle(.milliseconds(150))
            let editorManager = try #require(workspace.editorManager)
            let index = try #require(model.selectedFiles.firstIndex { $0.fileURL.lastPathComponent == "outside.txt" })
            let height = Islands.listRowHeight
            let point = CGPoint(x: 120, y: 4 + height + CGFloat(index) * height + height / 2)

            let menu = try input.contextMenu(at: point)
            let item = try #require(menu.items.firstIndex { $0.title == "Open File" })
            menu.performActionForItem(at: item)
            try await Task.sleep(for: .milliseconds(300))

            #expect(editorManager.activeEditor.tabs.isEmpty)
        }
    }

    @Test
    func changedFileRowForwardsEveryContextMenuItemAndColoursHover() async throws {
        let counters = RowCounters()
        let file = GitChangedFile(
            status: .modified,
            stagedStatus: .none,
            fileURL: URL(fileURLWithPath: "/repo/src/deep/file.swift"),
            originalFilename: nil
        )
        let hosted = HostedViewFixture.host(size: NSSize(width: 400, height: 80)) {
            VStack(spacing: 0) {
                GitLogChangedFileRow(
                    file: file,
                    directory: "src/deep",
                    onShowDiff: { counters.diffs += 1 },
                    onOpen: { counters.opens += 1 },
                    onOpenInNewWindow: { counters.newWindows += 1 },
                    onReveal: { counters.reveals += 1 }
                )
                Spacer()
            }
        }
        defer { hosted.close() }
        let input = GitToolWindowCovInput(hosted: hosted)
        try await hosted.settle(.milliseconds(100))
        #expect(hosted.renders())
        let center = CGPoint(x: 200, y: Islands.listRowHeight / 2)

        let menu = try input.contextMenu(at: center)
        let titles = ["Show Diff", "Open File", "Open in New Window", "Reveal in Project Navigator"]
        for title in titles {
            let index = try #require(menu.items.firstIndex { $0.title == title })
            menu.performActionForItem(at: index)
        }

        #expect(counters.diffs == 1)
        #expect(counters.opens == 1)
        #expect(counters.newWindows == 1)
        #expect(counters.reveals == 1)
    }

    @Test
    func changedFileRowHoverBackgroundIsHighlightedOnlyWhileHovering() {
        #expect(GitLogChangedFileRow.background(isHovering: true) == Islands.hover)
        #expect(GitLogChangedFileRow.background(isHovering: false) == Color.clear)
    }

    @Test
    func changedFileRowHoverSetterLeavesTheRowRendering() async throws {
        let file = GitChangedFile(
            status: .modified,
            stagedStatus: .none,
            fileURL: URL(fileURLWithPath: "/repo/src/deep/file.swift"),
            originalFilename: nil
        )
        let row = GitLogChangedFileRow(
            file: file,
            directory: "src/deep",
            onShowDiff: {},
            onOpen: {},
            onOpenInNewWindow: {},
            onReveal: {}
        )
        row.setHovering(true)
        row.setHovering(false)

        let hosted = HostedViewFixture.host(size: NSSize(width: 400, height: 40)) { row }
        defer { hosted.close() }
        try await hosted.settle(.milliseconds(100))
        #expect(hosted.renders())
    }

    @MainActor
    private final class RowCounters {
        var diffs = 0
        var opens = 0
        var newWindows = 0
        var reveals = 0
    }
}
