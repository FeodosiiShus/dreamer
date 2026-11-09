import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

@Suite
struct LSPWorkspaceEditConfinementTests {
    private func outsideFailure(_ uri: String, at index: UInt = 0) -> ApplyWorkspaceEditResult {
        LSPExecutorEdits.outsideFailure(uri, at: index)
    }

    @Test
    func deletingOutsideTheWorkspaceIsRefusedAndNothingIsRemoved() async throws {
        try await withTempDir { directory in
            let fixture = try LSPExecutorFixture(in: directory)
            let secret = try fixture.makeFile(in: fixture.outside, "secret.txt", "secret")
            let executor = fixture.executor()

            let single = await executor.apply(LSPExecutorEdits.delete(secret))
            let recursive = await executor.apply(LSPExecutorEdits.delete(fixture.outside, recursive: true))

            #expect(single == outsideFailure(secret.absoluteString))
            #expect(recursive == outsideFailure(fixture.outside.absoluteString))
            #expect(try String(contentsOf: secret, encoding: .utf8) == "secret")
            #expect(fixture.trashed.isEmpty)
        }
    }

    @Test
    func theWorkspaceRootItselfCannotBeDeleted() async throws {
        try await withTempDir { directory in
            let fixture = try LSPExecutorFixture(in: directory)
            let file = try fixture.makeFile(in: fixture.root, "a.txt", "a")

            let result = await fixture.executor().apply(LSPExecutorEdits.delete(fixture.root, recursive: true))

            #expect(result == outsideFailure(fixture.root.absoluteString))
            #expect(FileManager.default.fileExists(atPath: file.path))
            #expect(fixture.trashed.isEmpty)
        }
    }

    @Test
    func aSiblingFolderSharingTheRootNamePrefixIsOutside() async throws {
        try await withTempDir { directory in
            let fixture = try LSPExecutorFixture(in: directory)
            let sibling = try fixture.makeFolder(in: fixture.base, "workspace-other")
            let file = try fixture.makeFile(in: sibling, "a.txt", "a")

            let result = await fixture.executor().apply(LSPExecutorEdits.delete(file))

            #expect(result == outsideFailure(file.absoluteString))
            #expect(FileManager.default.fileExists(atPath: file.path))
        }
    }

    @Test
    func parentTraversalOutOfTheWorkspaceIsRefused() async throws {
        try await withTempDir { directory in
            let fixture = try LSPExecutorFixture(in: directory)
            let secret = try fixture.makeFile(in: fixture.outside, "secret.txt", "secret")
            let sneaky = fixture.root.absoluteString + "../outside/secret.txt"
            let deletion = try LSPExecutorEdits.decode(
                #"{"documentChanges":[{"kind":"delete","uri":"\#(sneaky)"}]}"#
            )

            let result = await fixture.executor().apply(deletion)

            #expect(result == outsideFailure(sneaky))
            #expect(FileManager.default.fileExists(atPath: secret.path))
        }
    }

    @Test
    func aSymlinkInsideTheWorkspaceCannotLeadOutOfIt() async throws {
        try await withTempDir { directory in
            let fixture = try LSPExecutorFixture(in: directory)
            let secret = try fixture.makeFile(in: fixture.outside, "secret.txt", "secret")
            try FileManager.default.createSymbolicLink(
                at: fixture.root.appending(path: "link"),
                withDestinationURL: fixture.outside
            )
            let throughLink = fixture.root.appending(path: "link/secret.txt")
            let created = fixture.root.appending(path: "link/created.txt")
            let creation = try LSPExecutorEdits.create(created.absoluteString)
            let executor = fixture.executor()

            let throughLinkDeletion = LSPExecutorEdits.delete(throughLink)
            #expect(await executor.apply(throughLinkDeletion) == outsideFailure(throughLink.absoluteString))
            #expect(await executor.apply(creation) == outsideFailure(created.absoluteString))
            #expect(try String(contentsOf: secret, encoding: .utf8) == "secret")
            #expect(!FileManager.default.fileExists(atPath: fixture.outside.appending(path: "created.txt").path))
            #expect(fixture.trashed.isEmpty)
        }
    }

    @Test
    func renamesMayNeitherStartNorEndOutsideTheWorkspace() async throws {
        try await withTempDir { directory in
            let fixture = try LSPExecutorFixture(in: directory)
            let inside = try fixture.makeFile(in: fixture.root, "inside.txt", "inside")
            let secret = try fixture.makeFile(in: fixture.outside, "secret.txt", "secret")
            let moved = fixture.outside.appending(path: "moved.txt")
            let taken = fixture.root.appending(path: "taken.txt")
            let leaving = try LSPExecutorEdits.rename(inside, moved)
            let entering = try LSPExecutorEdits.rename(secret, taken)
            let executor = fixture.executor()

            #expect(await executor.apply(leaving) == outsideFailure(moved.absoluteString))
            #expect(await executor.apply(entering) == outsideFailure(secret.absoluteString))
            #expect(try String(contentsOf: inside, encoding: .utf8) == "inside")
            #expect(try String(contentsOf: secret, encoding: .utf8) == "secret")
            #expect(!FileManager.default.fileExists(atPath: taken.path))
            #expect(!FileManager.default.fileExists(atPath: moved.path))
        }
    }

    @Test
    func creatingOutsideTheWorkspaceIsRefused() async throws {
        try await withTempDir { directory in
            let fixture = try LSPExecutorFixture(in: directory)
            let target = fixture.outside.appending(path: "new/created.txt")
            let creation = try LSPExecutorEdits.create(target.absoluteString)

            let result = await fixture.executor().apply(creation)

            #expect(result == outsideFailure(target.absoluteString))
            #expect(!FileManager.default.fileExists(atPath: fixture.outside.appending(path: "new").path))
        }
    }

    @Test
    func aRefusedFileOperationLeavesEarlierEditsOfTheSameRequestUnapplied() async throws {
        try await withTempDir { directory in
            let fixture = try LSPExecutorFixture(in: directory)
            let inside = try fixture.makeFile(in: fixture.root, "inside.txt", "keep")
            let target = fixture.outside.appending(path: "new.txt")
            let workspaceEdit = try LSPExecutorEdits.decode("""
            {"documentChanges":[
              {"textDocument":{"uri":"\(inside.absoluteString)","version":null},
               "edits":[{"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":4}},
                         "newText":"lost"}]},
              {"kind":"create","uri":"\(target.absoluteString)"}]}
            """)

            let result = await fixture.executor().apply(workspaceEdit)

            #expect(result == outsideFailure(target.absoluteString, at: 1))
            #expect(try String(contentsOf: inside, encoding: .utf8) == "keep")
            #expect(!FileManager.default.fileExists(atPath: target.path))
        }
    }

    @Test
    func operationsInsideTheWorkspaceStillRunWhenTheRootIsReachedThroughASymlink() async throws {
        try await withTempDir { directory in
            let fixture = try LSPExecutorFixture(in: directory)
            let alias = fixture.base.appending(path: "alias")
            try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: fixture.root)
            let file = try fixture.makeFile(in: fixture.root, "a.txt", "a")
            let executor = LSPWorkspaceEditExecutor(workspaceRoot: alias, trashItem: fixture.trashHandler)

            let result = await executor.apply(LSPExecutorEdits.delete(file))

            #expect(result.applied)
            #expect(fixture.trashed == [file.path])
        }
    }
}
