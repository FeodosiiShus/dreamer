import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct GitLogDetailsPaneMenuTests {
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

        func select(_ subject: String) async throws {
            let target = try #require(model.commits.first { $0.subject == subject })
            await model.select(hash: target.hash)
            try await hosted.settle(.milliseconds(150))
        }

        func fileRowPoint(_ index: Int) -> CGPoint {
            let height = Islands.listRowHeight
            return CGPoint(x: 120, y: 4 + height + CGFloat(index) * height + height / 2)
        }

        func menu(forFileAt index: Int) throws -> NSMenu {
            try input.contextMenu(at: fileRowPoint(index))
        }
    }

    private func makeSession(_ directory: URL, root: URL? = nil) async throws -> Session {
        let workspace = try HostedViewFixture.makeWorkspace(in: root ?? directory)
        let manager = try #require(workspace.sourceControlManager)
        let model = GitLogViewModel()
        await model.load(manager: manager)
        let hosted = try HostedViewFixture.hostInWorkspace(workspace) {
            GitLogDetailsPane(viewModel: model)
        }
        let input = GitToolWindowCovInput(hosted: hosted)
        try await hosted.settle(.milliseconds(150))
        return Session(workspace: workspace, manager: manager, model: model, hosted: hosted, input: input)
    }

    private func perform(_ title: String, in menu: NSMenu) throws {
        let index = try #require(menu.items.firstIndex { $0.title == title })
        menu.performActionForItem(at: index)
    }

    private func diffWindows(containing text: String) -> [NSWindow] {
        NSApp.windows.filter { $0.windowController is DiffViewerWindowController && $0.title.contains(text) }
    }

    private func codeDocuments(named name: String, in directory: URL) -> [CodeFileDocument] {
        NSDocumentController.shared.documents
            .compactMap { $0 as? CodeFileDocument }
            .filter {
                $0.fileURL?.lastPathComponent == name
                    && $0.fileURL?.path(percentEncoded: false).contains(directory.lastPathComponent) == true
            }
    }

    private func discard(_ documents: [CodeFileDocument]) {
        for document in documents {
            document.windowControllers.forEach { $0.window?.isReleasedWhenClosed = false }
            document.close()
        }
    }

    @MainActor
    private final class RowCounters {
        var diffs = 0
        var opens = 0
        var newWindows = 0
        var reveals = 0
    }

    @Test
    func fileMenuListsEveryActionInOrder() async throws {
        try await withTempDir { directory in
            _ = try await GitToolWindowCovRepo.make(in: directory)
            let session = try await makeSession(directory)
            defer { session.close() }
            try await session.select("Feature work")
            try await eventually(timeout: .seconds(10)) { session.model.selectedFiles.count == 2 }

            let menu = try session.menu(forFileAt: 0)

            #expect(menu.items.filter { !$0.isSeparatorItem }.map(\.title) == [
                "Show Diff",
                "Open File",
                "Open in New Window",
                "Reveal in Project Navigator"
            ])
        }
    }

    @Test
    func showDiffItemOpensTheCommitDiffWindow() async throws {
        try await withTempDir { directory in
            _ = try await GitToolWindowCovRepo.make(in: directory)
            let session = try await makeSession(directory)
            defer { session.close() }
            try await session.select("Feature work")
            let shortHash = try #require(session.model.selectedCommit).shortHash
            try await eventually(timeout: .seconds(10)) { session.model.selectedFiles.count == 2 }

            try perform("Show Diff", in: try session.menu(forFileAt: 0))

            try await eventually(timeout: .seconds(10)) { !diffWindows(containing: shortHash).isEmpty }
            let windows = diffWindows(containing: shortHash)
            #expect(windows.allSatisfy { $0.title.contains("feature.txt") })
            windows.forEach { $0.close() }
        }
    }

    @Test
    func openInNewWindowItemShowsTheFileInItsOwnWindow() async throws {
        try await withTempDir { directory in
            _ = try await GitToolWindowCovRepo.make(in: directory)
            let session = try await makeSession(directory)
            defer { session.close() }
            try await session.select("Feature work")
            try await eventually(timeout: .seconds(10)) { session.model.selectedFiles.count == 2 }

            try perform("Open in New Window", in: try session.menu(forFileAt: 0))

            let documents = codeDocuments(named: "feature.txt", in: directory)
            defer { discard(documents) }
            let document = try #require(documents.first)
            #expect(document.windowControllers.count == 1)
            #expect(document.windowControllers.first?.window != nil)

            try perform("Open in New Window", in: try session.menu(forFileAt: 0))

            #expect(document.windowControllers.count == 1)
        }
    }

    @Test
    func revealItemShowsTheProjectToolWindowAndHighlightsTheFile() async throws {
        try await withTempDir { directory in
            _ = try await GitToolWindowCovRepo.make(in: directory)
            let session = try await makeSession(directory)
            defer { session.close() }
            try await session.select("Feature work")
            try await eventually(timeout: .seconds(10)) { session.model.selectedFiles.count == 2 }
            session.workspace.toolWindowManager.hide(.project)
            #expect(session.workspace.toolWindowManager.isVisible(.project) == false)
            #expect(session.workspace.listenerModel.highlightedFileItem == nil)

            try perform("Reveal in Project Navigator", in: try session.menu(forFileAt: 0))

            #expect(session.workspace.toolWindowManager.isVisible(.project))
            #expect(session.workspace.listenerModel.highlightedFileItem?.url.lastPathComponent == "feature.txt")
        }
    }

    @Test
    func deletedFilesCannotBeOpenedInANewWindowOrRevealed() async throws {
        try await withTempDir { directory in
            _ = try await GitToolWindowCovRepo.make(in: directory)
            let session = try await makeSession(directory)
            defer { session.close() }
            try await session.select("Remove guide")
            #expect(session.model.selectedFiles.first?.status == .deleted)
            session.workspace.toolWindowManager.hide(.project)

            try perform("Open in New Window", in: try session.menu(forFileAt: 0))
            try perform("Reveal in Project Navigator", in: try session.menu(forFileAt: 0))

            #expect(codeDocuments(named: "guide.md", in: directory).isEmpty)
            #expect(session.workspace.toolWindowManager.isVisible(.project) == false)
            #expect(session.workspace.listenerModel.highlightedFileItem == nil)
        }
    }

    @Test
    func filesMissingFromTheWorkingTreeCannotBeOpenedInANewWindow() async throws {
        try await withTempDir { directory in
            _ = try await GitToolWindowCovRepo.make(in: directory)
            let session = try await makeSession(directory)
            defer { session.close() }
            try await session.select("Feature work")
            try await eventually(timeout: .seconds(10)) { session.model.selectedFiles.count == 2 }
            try FileManager.default.removeItem(at: directory.appending(path: "src/feature.txt"))

            try perform("Open in New Window", in: try session.menu(forFileAt: 0))

            #expect(codeDocuments(named: "feature.txt", in: directory).isEmpty)
        }
    }

    @Test
    func filesOutsideTheWorkspaceFolderCannotBeOpenedInANewWindowOrRevealed() async throws {
        try await withTempDir { directory in
            let fixture = try await GitMergeFixture(root: directory)
            try fixture.write("outside.txt", "outside\n")
            try fixture.write("sub/inside.txt", "inside\n")
            try await fixture.commit("both")
            let session = try await makeSession(directory, root: directory.appending(path: "sub"))
            defer { session.close() }
            let index = try #require(session.model.selectedFiles.firstIndex { $0.fileURL.lastPathComponent == "outside.txt" })
            session.workspace.toolWindowManager.hide(.project)

            try perform("Open in New Window", in: try session.menu(forFileAt: index))
            try perform("Reveal in Project Navigator", in: try session.menu(forFileAt: index))

            #expect(codeDocuments(named: "outside.txt", in: directory).isEmpty)
            #expect(session.workspace.toolWindowManager.isVisible(.project) == false)
            #expect(session.workspace.listenerModel.highlightedFileItem == nil)
        }
    }

    @Test
    func changedFileRowForwardsEveryMenuItem() async throws {
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
        let center = CGPoint(x: 200, y: Islands.listRowHeight / 2)

        for title in ["Show Diff", "Open File", "Open in New Window", "Reveal in Project Navigator"] {
            try perform(title, in: try input.contextMenu(at: center))
        }

        try await eventually(timeout: .seconds(10)) { counters.opens == 1 }
        #expect(counters.diffs == 1)
        #expect(counters.newWindows == 1)
        #expect(counters.reveals == 1)
    }
}
