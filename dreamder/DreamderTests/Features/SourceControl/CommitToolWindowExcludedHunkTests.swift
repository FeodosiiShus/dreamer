import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct CommitToolWindowExcludedHunkTests {
    private typealias Sample = CommitToolWindowSampleText

    private func makeRepo(_ directory: URL) async throws -> (GitMergeFixture, SourceControlManager) {
        let fixture = try await GitMergeFixture(root: directory)
        try fixture.write("a.txt", Sample.numbered())
        try await fixture.commit("initial")
        return (fixture, SourceControlManager(workspaceURL: directory, editorManager: EditorManager()))
    }

    private func expandedModel(
        _ manager: SourceControlManager
    ) async throws -> (CommitToolWindowViewModel, GitChangedFile) {
        let model = CommitToolWindowViewModel()
        let file = try #require(manager.changedFiles.first { $0.fileURL.lastPathComponent == "a.txt" })
        await model.toggleExpansion(of: file, using: manager)
        return (model, file)
    }

    private func excludeHunk(
        at index: Int,
        in model: CommitToolWindowViewModel,
        of file: GitChangedFile
    ) throws {
        let hunk = try #require(model.hunks(for: file).dropFirst(index).first)
        model.setHunkIncluded(false, hunk, in: file)
    }

    @Test
    func anExcludedHunkStaysExcludedWhenItsLineIsRewrittenAndTheRefreshReloadsIt() async throws {
        try await withTempDir { directory in
            let (fixture, manager) = try await makeRepo(directory)
            try fixture.write("a.txt", Sample.numbered(replacing: [2: "L2", 10: "L10", 19: "L19"]))
            await manager.refreshAllChangedFiles()
            let (model, file) = try await expandedModel(manager)
            try excludeHunk(at: 1, in: model, of: file)
            let excludedBefore = try #require(model.excludedHunkIDs[file.id])

            try fixture.write("a.txt", Sample.numbered(replacing: [2: "L2", 10: "L10 rewritten", 19: "L19"]))
            await model.refreshHunks(using: manager)

            let hunks = model.hunks(for: file)
            #expect(hunks.map(\.preview) == ["L2", "L10 rewritten", "L19"])
            #expect(model.excludedHunkIDs[file.id] == excludedBefore)
            #expect(model.isPartiallyIncluded(file))
            #expect(hunks.map { model.isHunkIncluded($0, in: file) } == [true, false, true])
        }
    }

    @Test
    func aPartialCommitLeavesARewrittenExcludedHunkOutEvenWithoutAnExplicitRefresh() async throws {
        try await withTempDir { directory in
            let (fixture, manager) = try await makeRepo(directory)
            try fixture.write("a.txt", Sample.numbered(replacing: [2: "L2", 10: "L10", 19: "L19"]))
            await manager.refreshAllChangedFiles()
            let (model, file) = try await expandedModel(manager)
            try excludeHunk(at: 1, in: model, of: file)
            let rewritten = Sample.numbered(replacing: [2: "L2", 10: "L10 rewritten\nand grown", 19: "L19"])
            try fixture.write("a.txt", rewritten)
            model.message = "Without the rewritten hunk"

            await model.commit(using: manager, andPush: false)

            #expect(manager.lastAlert == nil)
            #expect(
                try await fixture.run("show", "HEAD:a.txt") == Sample.numbered(replacing: [2: "L2", 19: "L19"])
            )
            #expect(try Data(contentsOf: directory.appending(path: "a.txt")) == Data(rewritten.utf8))
            #expect(try await fixture.stagedPaths().isEmpty)
            #expect(try await Sample.hunkCount(fixture, "diff", "-U0", "--", "a.txt") == 1)
        }
    }

    @Test
    func anExcludedHunkThatSplitsIntoTwoKeepsBothPiecesOutOfTheCommit() async throws {
        try await withTempDir { directory in
            let (fixture, manager) = try await makeRepo(directory)
            let wide: [Int: String] = [2: "L2", 10: "L10", 11: "L11", 12: "L12", 19: "L19"]
            try fixture.write("a.txt", Sample.numbered(replacing: wide))
            await manager.refreshAllChangedFiles()
            let (model, file) = try await expandedModel(manager)
            #expect(model.hunks(for: file).map(\.rangeTitle) == ["-2 +2", "-10,3 +10,3", "-19 +19"])
            try excludeHunk(at: 1, in: model, of: file)

            let split = Sample.numbered(replacing: [2: "L2", 10: "X10", 12: "X12", 19: "L19"])
            try fixture.write("a.txt", split)
            await model.refreshHunks(using: manager)

            let hunks = model.hunks(for: file)
            #expect(hunks.map(\.rangeTitle) == ["-2 +2", "-10 +10", "-12 +12", "-19 +19"])
            #expect(hunks.map { model.isHunkIncluded($0, in: file) } == [true, false, false, true])

            model.message = "Split"
            await model.commit(using: manager, andPush: false)

            #expect(
                try await fixture.run("show", "HEAD:a.txt") == Sample.numbered(replacing: [2: "L2", 19: "L19"])
            )
            #expect(try await Sample.hunkCount(fixture, "diff", "-U0", "--", "a.txt") == 2)
        }
    }

    @Test
    func aSplitThatHappensAfterTheLastRefreshIsStillHonouredByTheCommit() async throws {
        try await withTempDir { directory in
            let (fixture, manager) = try await makeRepo(directory)
            let wide: [Int: String] = [2: "L2", 10: "L10", 11: "L11", 12: "L12", 19: "L19"]
            try fixture.write("a.txt", Sample.numbered(replacing: wide))
            await manager.refreshAllChangedFiles()
            let (model, file) = try await expandedModel(manager)
            try excludeHunk(at: 1, in: model, of: file)
            try fixture.write("a.txt", Sample.numbered(replacing: [2: "L2", 10: "X10", 12: "X12", 19: "L19"]))
            model.message = "Split without refresh"

            await model.commit(using: manager, andPush: false)

            #expect(
                try await fixture.run("show", "HEAD:a.txt") == Sample.numbered(replacing: [2: "L2", 19: "L19"])
            )
            #expect(try await Sample.hunkCount(fixture, "diff", "-U0", "--", "a.txt") == 2)
        }
    }

    @Test
    func aHunkThatAppearsAfterTheExclusionIsIncludedByDefault() async throws {
        try await withTempDir { directory in
            let (fixture, manager) = try await makeRepo(directory)
            try fixture.write("a.txt", Sample.numbered(replacing: [2: "L2", 10: "L10"]))
            await manager.refreshAllChangedFiles()
            let (model, file) = try await expandedModel(manager)
            try excludeHunk(at: 1, in: model, of: file)

            try fixture.write("a.txt", Sample.numbered(replacing: [2: "L2", 10: "L10", 15: "L15"]))
            await model.refreshHunks(using: manager)

            let hunks = model.hunks(for: file)
            #expect(hunks.map(\.preview) == ["L2", "L10", "L15"])
            #expect(hunks.map { model.isHunkIncluded($0, in: file) } == [true, false, true])
            model.message = "New hunk"
            await model.commit(using: manager, andPush: false)
            #expect(
                try await fixture.run("show", "HEAD:a.txt") == Sample.numbered(replacing: [2: "L2", 15: "L15"])
            )
        }
    }

    @Test
    func aHunkWhoseChangeWasRevertedLeavesNoExclusionBehind() async throws {
        try await withTempDir { directory in
            let (fixture, manager) = try await makeRepo(directory)
            try fixture.write("a.txt", Sample.numbered(replacing: [2: "L2", 10: "L10", 19: "L19"]))
            await manager.refreshAllChangedFiles()
            let (model, file) = try await expandedModel(manager)
            try excludeHunk(at: 1, in: model, of: file)

            try fixture.write("a.txt", Sample.numbered(replacing: [2: "L2", 19: "L19"]))
            await model.refreshHunks(using: manager)

            #expect(model.excludedHunkIDs[file.id] == nil)
            #expect(model.isPartiallyIncluded(file) == false)
            #expect(model.isIncluded(file))
        }
    }

    @Test
    func aPartialSelectionThatTheClientReportsAsWholeFileIsStagedAndCommittedAsTheWholeFile() async throws {
        try await withTempDir { directory in
            let (fixture, manager) = try await makeRepo(directory)
            let edited = Sample.numbered(replacing: [2: "L2", 10: "L10", 19: "L19"])
            try fixture.write("a.txt", edited)
            await manager.refreshAllChangedFiles()
            let (model, file) = try await expandedModel(manager)
            try excludeHunk(at: 1, in: model, of: file)
            var requests: [String] = []
            model.stageHunks = { _, path, _ in
                requests.append(path)
                return .wholeFile
            }
            model.message = "Whole file"

            await model.commit(using: manager, andPush: false)

            #expect(requests == ["a.txt"])
            #expect(manager.lastAlert == nil)
            #expect(try await fixture.run("show", "HEAD:a.txt") == edited)
            #expect(try await fixture.stagedPaths().isEmpty)
            #expect(try await fixture.run("rev-list", "--count", "HEAD") == "2\n")
        }
    }
}
