import AppKit
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized)
struct DreamderDocumentControllerRoutingTests {
    private func makeWorkspace(at directory: URL) throws -> WorkspaceDocument {
        try WorkspaceDocument(for: directory, withContentsOf: directory, ofType: "")
    }

    private func openFileNames(in workspace: WorkspaceDocument) -> [String] {
        let files = workspace.editorManager?.editorLayout.gatherOpenFiles() ?? []
        return files.map(\.name).sorted()
    }

    @Test
    func openingAFileInsideAnOpenWorkspaceOpensATabInsteadOfANewDocument() throws {
        try withTempDir { directory in
            let fileURL = directory.appending(path: "Notes.txt")
            try "hello\n".write(to: fileURL, atomically: true, encoding: .utf8)
            let workspace = try makeWorkspace(at: directory)
            defer { workspace.close() }
            let controller = DreamderDocumentController()
            controller.addDocument(workspace)
            var completionCalls = 0

            controller.openDocument(withContentsOf: fileURL, display: true) { _, _, _ in
                completionCalls += 1
            }

            #expect(openFileNames(in: workspace) == ["Notes.txt"])
            #expect(workspace.editorManager?.activeEditor.selectedTab?.file.name == "Notes.txt")
            #expect(completionCalls == 0)
        }
    }

    @Test
    func openingAFileRoutesToTheWorkspaceNearestToTheFile() throws {
        try withTempDir { directory in
            let outerDirectory = directory.appending(path: "outer")
            let innerDirectory = outerDirectory.appending(path: "inner")
            try FileManager.default.createDirectory(at: innerDirectory, withIntermediateDirectories: true)
            let fileURL = innerDirectory.appending(path: "Deep.txt")
            try "deep\n".write(to: fileURL, atomically: true, encoding: .utf8)
            let outer = try makeWorkspace(at: outerDirectory)
            let inner = try makeWorkspace(at: innerDirectory)
            defer {
                outer.close()
                inner.close()
            }
            let controller = DreamderDocumentController()
            controller.addDocument(outer)
            controller.addDocument(inner)

            controller.openDocument(withContentsOf: fileURL, display: true) { _, _, _ in }

            #expect(openFileNames(in: inner) == ["Deep.txt"])
            #expect(openFileNames(in: outer).isEmpty)
        }
    }

    @Test
    func openingAFileRoutesToTheNearestWorkspaceRegardlessOfRegistrationOrder() throws {
        try withTempDir { directory in
            let outerDirectory = directory.appending(path: "outer")
            let innerDirectory = outerDirectory.appending(path: "inner")
            try FileManager.default.createDirectory(at: innerDirectory, withIntermediateDirectories: true)
            let fileURL = innerDirectory.appending(path: "Deep.txt")
            try "deep\n".write(to: fileURL, atomically: true, encoding: .utf8)
            let outer = try makeWorkspace(at: outerDirectory)
            let inner = try makeWorkspace(at: innerDirectory)
            defer {
                outer.close()
                inner.close()
            }
            let controller = DreamderDocumentController()
            controller.addDocument(inner)
            controller.addDocument(outer)

            controller.openDocument(withContentsOf: fileURL, display: true) { _, _, _ in }

            #expect(openFileNames(in: inner) == ["Deep.txt"])
            #expect(openFileNames(in: outer).isEmpty)
        }
    }

    @Test
    func openingAFileOutsideTheNearestWorkspaceFallsBackToAnEnclosingOne() throws {
        try withTempDir { directory in
            let outerDirectory = directory.appending(path: "outer")
            let innerDirectory = outerDirectory.appending(path: "inner")
            try FileManager.default.createDirectory(at: innerDirectory, withIntermediateDirectories: true)
            let fileURL = outerDirectory.appending(path: "Top.txt")
            try "top\n".write(to: fileURL, atomically: true, encoding: .utf8)
            let outer = try makeWorkspace(at: outerDirectory)
            let inner = try makeWorkspace(at: innerDirectory)
            defer {
                outer.close()
                inner.close()
            }
            let controller = DreamderDocumentController()
            controller.addDocument(inner)
            controller.addDocument(outer)

            controller.openDocument(withContentsOf: fileURL, display: true) { _, _, _ in }

            #expect(openFileNames(in: outer) == ["Top.txt"])
            #expect(openFileNames(in: inner).isEmpty)
        }
    }
}
