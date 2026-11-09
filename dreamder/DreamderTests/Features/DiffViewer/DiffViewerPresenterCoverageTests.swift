import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct DiffViewerPresenterCoverageTests {
    private struct Project {
        let root: URL
        let fixture: GitMergeFixture
        let workspace: WorkspaceDocument
        let manager: SourceControlManager
    }

    private func makeProject(_ dir: URL, files: [String: String]) async throws -> Project {
        let fixture = try await GitMergeFixture(root: dir)
        for (name, text) in files {
            try fixture.write(name, text)
        }
        try await fixture.commit("base")
        let workspace = WorkspaceDocument()
        let manager = SourceControlManager(workspaceURL: dir, editorManager: EditorManager())
        workspace.sourceControlManager = manager
        return Project(root: dir, fixture: fixture, workspace: workspace, manager: manager)
    }

    private func addParentWindow(to workspace: WorkspaceDocument) {
        let parent = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )
        parent.isReleasedWhenClosed = false
        workspace.addWindowController(NSWindowController(window: parent))
    }

    private func viewModel(of controller: DiffViewerWindowController) throws -> DiffViewerViewModel {
        let hosting = try #require(controller.contentViewController as? NSHostingController<DiffViewerView>)
        return hosting.rootView.model
    }

    private func headHash(_ fixture: GitMergeFixture) async throws -> String {
        try await fixture.run("rev-parse", "HEAD").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func modalCount(_ title: String) -> Int {
        DreamderHeadless.suppressedModals.filter { $0 == title }.count
    }

    private func close(_ keys: String...) {
        for key in keys {
            DiffViewerPresenter.windows[key]?.window?.close()
        }
    }

    @Test
    func fileDiffWithoutSourceControlOpensNothing() {
        let name = "\(UUID().uuidString).txt"
        DiffViewerPresenter.showFileDiff(
            workspace: WorkspaceDocument(),
            fileURL: URL(fileURLWithPath: "/tmp/\(name)")
        )
        #expect(DiffViewerPresenter.windows.keys.contains { $0.hasSuffix(name) } == false)
    }

    @Test
    func fileDiffOutsideTheRepositoryOrForTheRootItselfOpensNothing() async throws {
        try await withTempDir { dir in
            let project = try await makeProject(dir, files: ["keep.txt": "keep\n"])
            let outside = "\(UUID().uuidString).txt"

            DiffViewerPresenter.showFileDiff(
                workspace: project.workspace,
                fileURL: URL(fileURLWithPath: "/definitely/elsewhere/\(outside)")
            )
            DiffViewerPresenter.showFileDiff(workspace: project.workspace, fileURL: project.manager.repositoryURL)

            #expect(DiffViewerPresenter.windows.keys.contains { $0.hasSuffix(outside) } == false)
            #expect(DiffViewerPresenter.windows["worktree:HEAD:"] == nil)
        }
    }

    @Test
    func fileDiffOpensAWindowLoadsTheDiffAndFocusesItAgain() async throws {
        try await withTempDir { dir in
            let name = "\(UUID().uuidString).txt"
            let project = try await makeProject(dir, files: [name: "a\n"])
            try project.fixture.write(name, "b\n")
            addParentWindow(to: project.workspace)
            let key = "worktree:HEAD:\(name)"
            defer { close(key) }

            DiffViewerPresenter.showFileDiff(workspace: project.workspace, fileURL: dir.appending(path: name))

            let controller = try #require(DiffViewerPresenter.windows[key])
            let model = try viewModel(of: controller)
            try await eventually { model.diff != nil }
            #expect(model.title == "\(name) (HEAD vs Local)")
            #expect(model.selectedFile?.status == .modified)
            #expect(model.selectedFile?.left == .history(ref: "HEAD", path: name))
            #expect(model.diff?.rightLines == ["b"])

            try project.fixture.write(name, "c\n")
            DiffViewerPresenter.showFileDiff(workspace: project.workspace, fileURL: dir.appending(path: name))

            #expect(DiffViewerPresenter.windows[key] === controller)
            try await eventually { model.diff?.rightLines == ["c"] }

            controller.window?.close()
            #expect(DiffViewerPresenter.windows[key] == nil)
        }
    }

    @Test
    func fileDiffAgainstAnotherRefUsesItsOwnWindow() async throws {
        try await withTempDir { dir in
            let name = "\(UUID().uuidString).txt"
            let project = try await makeProject(dir, files: [name: "a\n"])
            let branch = "ref-\(UUID().uuidString)"
            try await project.fixture.run("branch", branch)
            try project.fixture.write(name, "b\n")
            let headKey = "worktree:HEAD:\(name)"
            let branchKey = "worktree:\(branch):\(name)"
            defer { close(headKey, branchKey) }

            DiffViewerPresenter.showFileDiff(workspace: project.workspace, fileURL: dir.appending(path: name))
            DiffViewerPresenter.showFileDiff(
                workspace: project.workspace,
                fileURL: dir.appending(path: name),
                against: branch
            )

            let head = try #require(DiffViewerPresenter.windows[headKey])
            let other = try #require(DiffViewerPresenter.windows[branchKey])
            #expect(head !== other)
            let otherModel = try viewModel(of: other)
            try await eventually { otherModel.diff != nil }
            #expect(otherModel.title == "\(name) (\(branch) vs Local)")
        }
    }

    @Test
    func fileDiffUsesTheChangedFileStatusAndOriginalName() async throws {
        try await withTempDir { dir in
            let id = UUID().uuidString
            let oldName = "\(id)-old.txt"
            let newName = "\(id)-new.txt"
            let project = try await makeProject(dir, files: [oldName: "x1\nx2\nx3\n", "\(id)-other.txt": "o\n"])
            try await project.fixture.run("mv", oldName, newName)
            try project.fixture.write(newName, "x1\nx2\nx3\nx4\n")
            project.manager.changedFiles = [
                GitChangedFile(
                    status: .none,
                    stagedStatus: .modified,
                    fileURL: project.manager.repositoryURL.appending(path: "\(id)-other.txt"),
                    originalFilename: nil
                ),
                GitChangedFile(
                    status: .none,
                    stagedStatus: .renamed,
                    fileURL: project.manager.repositoryURL.appending(path: newName),
                    originalFilename: oldName
                )
            ]
            let key = "worktree:HEAD:\(newName)"
            defer { close(key) }

            DiffViewerPresenter.showFileDiff(
                workspace: project.workspace,
                fileURL: project.manager.repositoryURL.appending(path: newName)
            )

            let controller = try #require(DiffViewerPresenter.windows[key])
            let model = try viewModel(of: controller)
            let request = try #require(model.selectedFile)
            #expect(request.status == .renamed)
            #expect(request.originalPath == oldName)
            #expect(request.left == .history(ref: "HEAD", path: oldName))
            try await eventually { model.diff != nil }
            #expect(model.differenceSummary == "1 difference")
        }
    }

    @Test
    func commitFileDiffOpensAWindowAgainstTheParentAndFocusesItAgain() async throws {
        try await withTempDir { dir in
            let name = "\(UUID().uuidString).txt"
            let project = try await makeProject(dir, files: [name: "a\n"])
            let parent = try await headHash(project.fixture)
            try project.fixture.write(name, "b\n")
            try await project.fixture.commit("second")
            let head = try await headHash(project.fixture)
            addParentWindow(to: project.workspace)
            let key = "commit:\(head):\(parent):\(name)"
            defer { close(key) }

            DiffViewerPresenter.showCommitFileDiff(
                workspace: project.workspace,
                commitHash: head,
                parentHash: parent,
                path: name
            )

            let controller = try #require(DiffViewerPresenter.windows[key])
            let model = try viewModel(of: controller)
            try await eventually { model.diff != nil }
            #expect(model.title == "\(name) (\(parent.prefix(8)) vs \(head.prefix(8)))")
            #expect(model.diff?.leftLines == ["a"])
            #expect(model.diff?.rightLines == ["b"])

            DiffViewerPresenter.showCommitFileDiff(
                workspace: project.workspace,
                commitHash: head,
                parentHash: parent,
                path: name
            )

            #expect(DiffViewerPresenter.windows[key] === controller)
            try await eventually { model.diff != nil }
        }
    }

    @Test
    func commitFileDiffOfTheRootCommitComparesAgainstNothing() async throws {
        try await withTempDir { dir in
            let name = "\(UUID().uuidString).txt"
            let project = try await makeProject(dir, files: [name: "first\n"])
            let root = try await headHash(project.fixture)
            let key = "commit:\(root)::\(name)"
            defer { close(key) }

            DiffViewerPresenter.showCommitFileDiff(
                workspace: project.workspace,
                commitHash: root,
                parentHash: nil,
                path: name
            )

            let controller = try #require(DiffViewerPresenter.windows[key])
            let model = try viewModel(of: controller)
            try await eventually { model.diff != nil }
            #expect(model.title == "\(name) (Empty vs \(root.prefix(8)))")
            #expect(model.diff?.leftLines.isEmpty == true)
            #expect(model.diff?.rightLines == ["first"])
        }
    }

    @Test
    func commitFileDiffRejectsMissingRepositoryAndEmptyPath() async throws {
        try await withTempDir { dir in
            let project = try await makeProject(dir, files: ["keep.txt": "keep\n"])
            let hash = "deadbeef\(UUID().uuidString)"

            DiffViewerPresenter.showCommitFileDiff(
                workspace: WorkspaceDocument(),
                commitHash: hash,
                parentHash: nil,
                path: "keep.txt"
            )
            DiffViewerPresenter.showCommitFileDiff(
                workspace: project.workspace,
                commitHash: hash,
                parentHash: nil,
                path: ""
            )

            #expect(DiffViewerPresenter.windows.keys.contains { $0.contains(hash) } == false)
        }
    }

    @Test
    func workingTreeDiffOpensAWindowAndUpdatesItOnTheNextRequest() async throws {
        try await withTempDir { dir in
            let id = UUID().uuidString
            let first = "\(id)-a.txt"
            let second = "\(id)-b.txt"
            let project = try await makeProject(dir, files: [first: "a\n", second: "b\n"])
            let branch = "all-\(id)"
            try await project.fixture.run("branch", branch)
            try project.fixture.write(first, "a2\n")
            try project.fixture.write(second, "b2\n")
            addParentWindow(to: project.workspace)
            let key = "worktree-all:\(branch)"
            defer { close(key) }

            DiffViewerPresenter.showWorkingTreeDiff(workspace: project.workspace, against: branch)

            try await eventually { DiffViewerPresenter.windows[key] != nil }
            let controller = try #require(DiffViewerPresenter.windows[key])
            let model = try viewModel(of: controller)
            #expect(model.files.map(\.path) == [first, second])
            #expect(model.showsFileList)
            try await eventually { model.diff != nil }
            #expect(model.title == "\(first) (\(branch) vs Local)")

            try await project.fixture.run("checkout", "--", first)
            DiffViewerPresenter.showWorkingTreeDiff(workspace: project.workspace, against: branch)

            try await eventually { model.files.count == 1 }
            #expect(DiffViewerPresenter.windows[key] === controller)
            try await eventually { model.selectedID == second }
            try await eventually { model.diff?.rightLines == ["b2"] }

            controller.window?.close()
            #expect(DiffViewerPresenter.windows[key] == nil)
        }
    }

    @Test
    func workingTreeDiffWithoutRepositoryDoesNothing() async throws {
        let ref = "none-\(UUID().uuidString)"

        DiffViewerPresenter.showWorkingTreeDiff(workspace: WorkspaceDocument(), against: ref)
        try await Task.sleep(for: .milliseconds(100))

        #expect(DiffViewerPresenter.windows["worktree-all:\(ref)"] == nil)
    }

    @Test
    func workingTreeDiffOfACleanTreeShowsTheNoDifferencesAlert() async throws {
        try await withTempDir { dir in
            let project = try await makeProject(dir, files: ["keep.txt": "keep\n"])
            let branch = "clean-\(UUID().uuidString)"
            try await project.fixture.run("branch", branch)
            let before = modalCount("No Differences")

            DiffViewerPresenter.showWorkingTreeDiff(workspace: project.workspace, against: branch)

            try await eventually { modalCount("No Differences") > before }
            #expect(DiffViewerPresenter.windows["worktree-all:\(branch)"] == nil)
        }
    }

    @Test
    func workingTreeDiffAgainstAnUnknownRefShowsTheFailureAlert() async throws {
        try await withTempDir { dir in
            let project = try await makeProject(dir, files: ["keep.txt": "keep\n"])
            let ref = "no-such-ref-\(UUID().uuidString)"
            let before = modalCount("Failed to load changes")

            DiffViewerPresenter.showWorkingTreeDiff(workspace: project.workspace, against: ref)

            try await eventually { modalCount("Failed to load changes") > before }
            #expect(DiffViewerPresenter.windows["worktree-all:\(ref)"] == nil)
        }
    }

    @Test
    func errorDescriptionsPreferTheGitMessageAndFallBackToTheLocalizedText() {
        #expect(DiffViewerPresenter.describe(GitClient.GitClientError.notGitRepository) == "Not a git repository")
        #expect(DiffViewerPresenter.describe(GitClient.GitClientError.outputError("fatal: boom")) == "fatal: boom")
        let foreign = NSError(domain: "DiffViewerPresenterCoverage", code: 7, userInfo: [NSLocalizedDescriptionKey: "plain failure"])
        #expect(DiffViewerPresenter.describe(foreign) == "plain failure")
    }
}
