import AppKit
import Foundation
import Testing
@testable import Dreamder

@MainActor
private final class UpdateObserver: CEWorkspaceFileManagerObserver {
    private(set) var updates: [Set<CEWorkspaceFile>] = []

    func fileManagerUpdated(updatedItems: Set<CEWorkspaceFile>) {
        updates.append(updatedItems)
    }
}

@MainActor
@Suite(.uiGate)
struct SourceControlManagerStatusTests {
    private struct Rig {
        let fixture: GitMergeFixture
        let manager: SourceControlManager
        let fileManager: CEWorkspaceFileManager
    }

    private func makeRig(_ dir: URL, prepare: (GitMergeFixture) throws -> Void = { _ in }) async throws -> Rig {
        let fixture = try await GitMergeFixture(root: dir)
        try fixture.write("a.txt", "one\n")
        try fixture.write("src/main.swift", "print(1)\n")
        try await fixture.commit("initial")
        try prepare(fixture)
        let manager = SourceControlManager(workspaceURL: dir, editorManager: EditorManager())
        let fileManager = CEWorkspaceFileManager(
            folderUrl: dir,
            ignoredFilesAndFolders: [".git"],
            sourceControlManager: manager
        )
        manager.fileManager = fileManager
        fileManager.fsEventStream?.cancel()
        fileManager.eventBatcher?.cancel()
        return Rig(fixture: fixture, manager: manager, fileManager: fileManager)
    }

    private func path(_ dir: URL, _ relative: String) -> String {
        dir.appending(path: relative).path(percentEncoded: false)
    }

    private func openDocument(_ url: URL) throws -> CodeFileDocument {
        let document = try CodeFileDocument(for: url, withContentsOf: url, ofType: "public.plain-text")
        NSDocumentController.shared.addDocument(document)
        return document
    }

    @Test
    func statusAsksGitForNormalUntrackedMode() async throws {
        let runner = FakeProcessRunner { _ in FakeProcessRunner.output("") }
        let client = GitClient(
            directoryURL: URL(filePath: "/repo", directoryHint: .isDirectory),
            commandRunner: GitCommandRunner(
                runner: runner,
                gitExecutable: URL(fileURLWithPath: "/usr/bin/git"),
                baseEnvironment: { [:] }
            )
        )

        _ = try await client.getStatus()

        let arguments = try #require(runner.invocations.first { $0.arguments.contains("status") }?.arguments)
        #expect(arguments.contains("-unormal"))
        #expect(arguments.contains("-u") == false)
        #expect(arguments.contains("--porcelain=2"))
        #expect(arguments.contains("-z"))
    }

    @Test
    func untrackedDirectoriesAppearAsOneEntry() async throws {
        try await withTempDir { dir in
            let rig = try await makeRig(dir)
            try rig.fixture.write("newdir/one.txt", "1\n")
            try rig.fixture.write("newdir/deep/two.txt", "2\n")
            try rig.fixture.write("loose.txt", "3\n")

            let status = try await rig.manager.gitClient.getStatus()

            #expect(status.untrackedFiles.map(\.fileURL.lastPathComponent).sorted() == ["loose.txt", "newdir"])
            let directory = try #require(status.untrackedFiles.first { $0.fileURL.lastPathComponent == "newdir" })
            #expect(directory.fileURL.hasDirectoryPath)
            #expect(directory.status == .untracked)
        }
    }

    @Test
    func conflictedFilesAreSurfacedFirstAsUnmergedAndNotStaged() async throws {
        try await withTempDir { dir in
            _ = try await GitMergeFixture.mergeConflict(in: dir)
            let manager = SourceControlManager(workspaceURL: dir, editorManager: EditorManager())

            await manager.refreshAllChangedFiles()

            let names = manager.changedFiles.map(\.fileURL.lastPathComponent)
            #expect(names.sorted() == ["config.txt", "notes.txt"])
            #expect(manager.changedFiles.allSatisfy { $0.anyStatus() == .unmerged })
            #expect(manager.changedFiles.allSatisfy { $0.stagedStatus == GitStatus.none && !$0.isStaged })
        }
    }

    @Test
    func conflictsComeBeforeOrdinaryChanges() async throws {
        try await withTempDir { dir in
            let fixture = try await GitMergeFixture.mergeConflict(in: dir)
            try fixture.write("aaa-new.txt", "new\n")
            let manager = SourceControlManager(workspaceURL: dir, editorManager: EditorManager())

            await manager.refreshAllChangedFiles()

            #expect(manager.changedFiles.count == 3)
            #expect(manager.changedFiles.prefix(2).allSatisfy { $0.anyStatus() == .unmerged })
            #expect(manager.changedFiles.last?.fileURL.lastPathComponent == "aaa-new.txt")
        }
    }

    @Test
    func refreshWithoutAFileManagerOnlyUpdatesTheChangedFileList() async throws {
        try await withTempDir { dir in
            let fixture = try await GitMergeFixture(root: dir)
            try fixture.write("a.txt", "one\n")
            try await fixture.commit("initial")
            try fixture.write("a.txt", "two\n")
            let manager = SourceControlManager(workspaceURL: dir, editorManager: EditorManager())

            await manager.refreshAllChangedFiles()

            #expect(manager.changedFiles.map(\.fileURL.lastPathComponent) == ["a.txt"])
        }
    }

    @Test
    func refreshMarksChangedAndUntrackedItemsInTheProjectTreeAndClearsThemAfterwards() async throws {
        try await withTempDir { dir in
            let rig = try await makeRig(dir) { fixture in
                try fixture.write("a.txt", "changed\n")
                try fixture.write("newdir/one.txt", "1\n")
            }
            let observer = UpdateObserver()
            rig.fileManager.addObserver(observer)

            await rig.manager.refreshAllChangedFiles()

            let changed = try #require(rig.fileManager.getFile(path(dir, "a.txt")))
            let untracked = try #require(rig.fileManager.getFile(path(dir, "newdir")))
            let clean = try #require(rig.fileManager.getFile(path(dir, "src")))
            #expect(changed.gitStatus == .modified)
            #expect(untracked.gitStatus == .untracked)
            #expect(clean.gitStatus == nil)
            #expect(observer.updates.contains { $0.contains(changed) && $0.contains(untracked) })

            await rig.fileManager.loadChildren(of: untracked)
            let child = try #require(rig.fileManager.getFile(path(dir, "newdir/one.txt")))
            #expect(child.gitStatus == .untracked)

            try await rig.fixture.commit("everything")
            await rig.manager.refreshAllChangedFiles()

            #expect(changed.gitStatus == nil)
            #expect(untracked.gitStatus == nil)
            #expect(child.gitStatus == nil)
            #expect(observer.updates.last?.contains(child) == true)
        }
    }

    @Test
    func debouncedRefreshWaitsForTheDebounceWindowBeforeReadingStatus() async throws {
        try await withTempDir { dir in
            let rig = try await makeRig(dir)
            try await Task.sleep(for: .milliseconds(400))
            await rig.manager.refreshAllChangedFiles()
            #expect(rig.manager.changedFiles.isEmpty)
            try rig.fixture.write("new.txt", "new\n")
            let clock = ContinuousClock()
            let start = clock.now

            await rig.manager.refreshAllChangedFiles(debounced: true)

            #expect(SourceControlManager.statusRefreshDebounce >= .milliseconds(500))
            #expect(clock.now - start >= .milliseconds(450))
            #expect(rig.manager.changedFiles.map(\.fileURL.lastPathComponent) == ["new.txt"])
        }
    }

    @Test
    func discardingChangesReloadsTheOpenDocument() async throws {
        try await withTempDir { dir in
            let rig = try await makeRig(dir)
            let url = dir.appending(path: "a.txt")
            try rig.fixture.write("a.txt", "dirty\n")
            let document = try openDocument(url)
            defer { NSDocumentController.shared.removeDocument(document) }
            #expect(document.content?.string == "dirty\n")

            rig.manager.discardChanges(for: url)

            try await eventually { document.content?.string == "one\n" }
            #expect(try rig.fixture.read("a.txt") == "one\n")
            #expect(document.isDocumentEdited == false)
        }
    }

    @Test
    func discardingChangesReplacesUnsavedEditsInTheOpenDocument() async throws {
        try await withTempDir { dir in
            let rig = try await makeRig(dir)
            let url = dir.appending(path: "a.txt")
            try rig.fixture.write("a.txt", "dirty\n")
            let document = try openDocument(url)
            defer { NSDocumentController.shared.removeDocument(document) }
            document.content?.mutableString.setString("typed but unsaved\n")
            document.updateChangeCount(.changeDone)
            #expect(document.isDocumentEdited)

            rig.manager.discardChanges(for: url)

            try await eventually { document.content?.string == "one\n" && !document.isDocumentEdited }
        }
    }

    @Test
    func discardingEverythingReloadsOnlyDocumentsInsideTheRepository() async throws {
        try await withTempDir { dir in
            let rig = try await makeRig(dir)
            try rig.fixture.write("a.txt", "dirty a\n")
            try rig.fixture.write("src/main.swift", "dirty main\n")
            let first = try openDocument(dir.appending(path: "a.txt"))
            let second = try openDocument(dir.appending(path: "src/main.swift"))
            try await withTempDir { outsideDir in
                let outsideURL = outsideDir.appending(path: "outside.txt")
                try "outside\n".write(to: outsideURL, atomically: true, encoding: .utf8)
                let outside = try openDocument(outsideURL)
                defer {
                    NSDocumentController.shared.removeDocument(first)
                    NSDocumentController.shared.removeDocument(second)
                    NSDocumentController.shared.removeDocument(outside)
                }
                outside.content?.mutableString.setString("in-memory edit\n")

                rig.manager.discardAllChanges()

                try await eventually {
                    first.content?.string == "one\n" && second.content?.string == "print(1)\n"
                }
                #expect(outside.content?.string == "in-memory edit\n")
            }
        }
    }

    @Test
    func reloadingADocumentWhoseFileVanishedKeepsItsContent() async throws {
        try withTempDir { dir in
            let url = dir.appending(path: "gone.txt")
            try "kept\n".write(to: url, atomically: true, encoding: .utf8)
            let document = try CodeFileDocument(for: url, withContentsOf: url, ofType: "public.plain-text")
            try FileManager.default.removeItem(at: url)

            document.reloadContentDiscardingEdits()

            #expect(document.content?.string == "kept\n")
        }
    }

    @Test
    func reloadingADocumentWithoutAFileDoesNothing() {
        let document = CodeFileDocument()
        document.content = NSTextStorage(string: "scratch")

        document.reloadContentDiscardingEdits()

        #expect(document.content?.string == "scratch")
    }
}
