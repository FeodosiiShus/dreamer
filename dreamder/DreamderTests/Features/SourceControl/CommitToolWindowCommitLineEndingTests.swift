import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct CommitToolWindowCommitLineEndingTests {
    private typealias Sample = CommitToolWindowSampleText

    @Test(arguments: CommitToolWindowLineEndingSetup.allCases)
    func aPartialCommitOfACrlfWorktreeCommitsLfBlobsAndKeepsTheWorktreeBytes(
        setup: CommitToolWindowLineEndingSetup
    ) async throws {
        try await withTempDir { directory in
            let fixture = try await GitMergeFixture(root: directory)
            try await setup.apply(to: fixture)
            try fixture.write("a.txt", Sample.numbered())
            try await fixture.commit("initial")
            let edited = Sample.numbered(replacing: [2: "L2", 10: "L10", 19: "L19"], lineEnding: "\r\n")
            try fixture.write("a.txt", edited)
            let manager = SourceControlManager(workspaceURL: directory, editorManager: EditorManager())
            await manager.refreshAllChangedFiles()
            let file = try #require(manager.changedFiles.first { $0.fileURL.lastPathComponent == "a.txt" })
            let model = CommitToolWindowViewModel()
            await model.toggleExpansion(of: file, using: manager)
            let middle = try #require(model.hunks(for: file).dropFirst().first)
            model.setHunkIncluded(false, middle, in: file)
            model.message = "Partial"

            await model.commit(using: manager, andPush: false)

            #expect(manager.lastAlert == nil)
            let committed = try await fixture.run("show", "HEAD:a.txt")
            #expect(committed == Sample.numbered(replacing: [2: "L2", 19: "L19"]))
            #expect(committed.utf8.contains(UInt8(ascii: "\r")) == false)
            #expect(try Data(contentsOf: directory.appending(path: "a.txt")) == Data(edited.utf8))
            #expect(try await fixture.stagedPaths().isEmpty)
            #expect(try await Sample.hunkCount(fixture, "diff", "-U0", "--", "a.txt") == 1)
        }
    }
}
