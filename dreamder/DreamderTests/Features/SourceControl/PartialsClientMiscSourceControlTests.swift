import AppKit
import Foundation
import Testing
@testable import Dreamder

@MainActor
private final class PartialsClientMiscFinishedCloneModel: GitCloneViewModel {
    private let finishedURL: URL

    init(finishedURL: URL, gitClient: GitClient?) {
        self.finishedURL = finishedURL
        super.init()
        self.gitClient = gitClient
    }

    override func cloneRepository(completionHandler: @escaping (URL) -> Void) {
        completionHandler(finishedURL)
    }
}

@MainActor
@Suite(.uiGate)
struct PartialsClientMiscCloneViewTests {
    private let recorder = GitCloneCoverageRecorder()

    private func makeView(model: GitCloneViewModel) -> GitCloneView {
        let recorder = recorder
        return GitCloneView(
            viewModel: model,
            openBranchView: { recorder.branchViews.append($0) },
            openDocument: { recorder.documents.append($0) }
        )
    }

    @Test
    func aFinishedCloneWithoutAGitClientOpensNothing() async throws {
        let location = URL(fileURLWithPath: "/tmp/partials-client-misc-clone", isDirectory: true)
        let model = PartialsClientMiscFinishedCloneModel(finishedURL: location, gitClient: nil)

        makeView(model: model).cloneRepository()
        try await Task.sleep(for: .milliseconds(100))

        #expect(recorder.documents.isEmpty)
        #expect(recorder.branchViews.isEmpty)
    }

    @Test
    func aFinishedCloneWhoseBranchListCannotBeReadOpensTheDocument() async throws {
        let location = URL(fileURLWithPath: "/tmp/partials-client-misc-clone", isDirectory: true)
        let failing = ScmFakeGit.client { _ in ScmFakeGit.failure("fatal: not a git repository") }.client
        let model = PartialsClientMiscFinishedCloneModel(finishedURL: location, gitClient: failing)

        makeView(model: model).cloneRepository()
        try await eventually(timeout: .seconds(30)) { !recorder.documents.isEmpty }

        #expect(recorder.documents == [location])
        #expect(recorder.branchViews.isEmpty)
    }
}

@MainActor
@Suite(.uiGate)
struct PartialsClientMiscManagerTests {
    @Test
    func branchExistenceIsFalseWhenGitCannotAnswer() async throws {
        try await withTempDir { directory in
            let manager = SourceControlManager(workspaceURL: directory, editorManager: EditorManager())

            #expect(manager.isGitRepository == false)
            #expect(await manager.branchOpsBranchExists("main") == false)
        }
    }
}

@Suite
struct PartialsClientMiscShelfFileTests {
    @Test
    func unknownStatusLettersAreListedAsModifiedAndFilesAreSortedByPath() async throws {
        let (client, _) = ScmFakeGit.client { _ in
            ScmFakeGit.ok("X\0odd.txt\0A\0added.txt\0D\0gone.txt\0")
        }

        let files = try await client.shelfFiles(of: "abc")

        #expect(files == [
            GitShelfFile(status: .added, path: "added.txt"),
            GitShelfFile(status: .deleted, path: "gone.txt"),
            GitShelfFile(status: .modified, path: "odd.txt")
        ])
    }
}

@MainActor
@Suite(.uiGate)
struct PartialsClientMiscCommitHunkTests {
    private func numbered(replacing replacements: [Int: String] = [:]) -> String {
        (1...20).map { "\(replacements[$0] ?? "l\($0)")\n" }.joined()
    }

    @Test
    func refreshingDropsTheExclusionOfAHunkThatNoLongerExistsAndKeepsTheFileIncluded() async throws {
        try await withTempDir { directory in
            let fixture = try await GitMergeFixture(root: directory)
            try fixture.write("a.txt", numbered())
            try await fixture.commit("initial")
            let manager = SourceControlManager(workspaceURL: directory, editorManager: EditorManager())
            try fixture.write("a.txt", numbered(replacing: [2: "L2", 10: "L10", 19: "L19"]))
            await manager.refreshAllChangedFiles()
            let changed = try #require(manager.changedFiles.first { $0.fileURL.lastPathComponent == "a.txt" })
            let model = CommitToolWindowViewModel()
            await model.toggleExpansion(of: changed, using: manager)
            let middle = try #require(model.hunks(for: changed).dropFirst().first)
            model.setHunkIncluded(false, middle, in: changed)
            #expect(model.isPartiallyIncluded(changed))

            try fixture.write("a.txt", numbered(replacing: [2: "L2", 19: "L19"]))
            await model.refreshHunks(using: manager)

            #expect(model.hunks(for: changed).map(\.preview) == ["L2", "L19"])
            #expect(model.excludedHunkIDs[changed.id] == nil)
            #expect(model.isPartiallyIncluded(changed) == false)
            #expect(model.isIncluded(changed))
        }
    }
}
