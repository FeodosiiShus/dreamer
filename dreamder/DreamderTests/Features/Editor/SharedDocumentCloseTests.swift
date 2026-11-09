import AppKit
import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct SharedDocumentCloseTests {
    private struct Setup {
        let workspace: WorkspaceDocument
        let manager: EditorManager
        let first: Editor
        let second: Editor
        let file: CEWorkspaceFile
    }

    private func makeSetup(in directory: URL) throws -> Setup {
        let url = directory.appending(path: "shared.txt")
        try "hello".write(to: url, atomically: true, encoding: .utf8)
        let workspace = try HostedViewFixture.makeWorkspace(in: directory)
        let manager = try #require(workspace.editorManager)
        let first = manager.activeEditor
        first.workspace = workspace
        let file = CEWorkspaceFile(url: url)
        first.openTab(file: file, asTemporary: false)
        let second = try #require(manager.split(first, .trailing, workspace: workspace))
        return Setup(workspace: workspace, manager: manager, first: first, second: second, file: file)
    }

    @Test
    func closingOneSplitKeepsTheDocumentAlive() throws {
        try withTempDir { dir in
            let setup = try makeSetup(in: dir)
            let document = try #require(setup.file.fileDocument)
            #expect(setup.second.tabs.contains { $0.file == setup.file })

            setup.first.closeTab(file: setup.file)

            #expect(setup.file.fileDocument === document)
            #expect(document.content != nil)
            #expect(!setup.first.tabs.contains { $0.file == setup.file })
        }
    }

    @Test
    func documentRemainsEditableAfterOtherSplitClosed() throws {
        try withTempDir { dir in
            let setup = try makeSetup(in: dir)
            let document = try #require(setup.file.fileDocument)

            setup.first.closeTab(file: setup.file)
            document.content?.replaceCharacters(in: NSRange(location: 0, length: 0), with: "x")
            document.updateChangeCount(.changeDone)

            #expect(document.isDocumentEdited)
            #expect(setup.file.fileDocument === document)
        }
    }

    @Test
    func closingTheLastSplitReleasesTheDocument() throws {
        try withTempDir { dir in
            let setup = try makeSetup(in: dir)

            setup.first.closeTab(file: setup.file)
            setup.second.closeTab(file: setup.file)

            #expect(setup.file.fileDocument == nil)
        }
    }

    @Test
    func closingFileOpenInSingleEditorReleasesTheDocument() throws {
        try withTempDir { dir in
            let url = dir.appending(path: "single.txt")
            try "one".write(to: url, atomically: true, encoding: .utf8)
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            let manager = try #require(workspace.editorManager)
            let editor = manager.activeEditor
            editor.workspace = workspace
            let file = CEWorkspaceFile(url: url)
            editor.openTab(file: file, asTemporary: false)
            #expect(file.fileDocument != nil)

            editor.closeTab(file: file)

            #expect(file.fileDocument == nil)
            #expect(editor.tabs.isEmpty)
        }
    }

    @Test
    func dirtyDocumentClosesInOneSplitWithoutPromptOrReset() throws {
        try withTempDir { dir in
            let setup = try makeSetup(in: dir)
            let document = try #require(setup.file.fileDocument)
            document.updateChangeCount(.changeDone)
            #expect(document.isDocumentEdited)

            setup.first.closeTab(file: setup.file)

            #expect(document.isDocumentEdited)
            #expect(setup.file.fileDocument === document)
            #expect(!setup.first.tabs.contains { $0.file == setup.file })
        }
    }

    @Test
    func temporaryTabInAnotherEditorCountsAsShown() throws {
        try withTempDir { dir in
            let setup = try makeSetup(in: dir)
            let document = try #require(setup.file.fileDocument)
            setup.second.tabs.removeAll()
            #expect(setup.second.temporaryTab?.file == setup.file)

            setup.first.closeTab(file: setup.file)

            #expect(setup.file.fileDocument === document)
        }
    }

    @Test
    func moveTabToNewSplitKeepsTheDocumentAlive() throws {
        try withTempDir { dir in
            let setup = try makeSetup(in: dir)
            let document = try #require(setup.file.fileDocument)
            document.updateChangeCount(.changeDone)

            let moved = try #require(
                setup.manager.moveTabToNewSplit(setup.file, from: setup.first, edge: .bottom, workspace: setup.workspace)
            )

            #expect(setup.file.fileDocument === document)
            #expect(document.isDocumentEdited)
            #expect(!setup.first.tabs.contains { $0.file == setup.file })
            #expect(moved.tabs.contains { $0.file == setup.file })
            #expect(moved.selectedTab?.file == setup.file)
            #expect(setup.manager.activeEditor === moved)
        }
    }

    @Test
    func editorWithoutManagerCountsTabsInItsOwnSplitTree() throws {
        let file = CEWorkspaceFile(url: URL(filePath: "/fake/solo.txt"))
        let first = Editor(files: [file])
        let second = Editor(files: [file])
        let data = SplitViewData(.horizontal, editorLayouts: [.one(first), .one(second)])
        first.parent = data
        second.parent = data

        first.closeTab(file: file)

        #expect(first.tabs.isEmpty)
        #expect(second.tabs.contains { $0.file == file })
    }

    @Test
    func unsplitMergesTabsWithoutClosingDocuments() throws {
        try withTempDir { dir in
            let setup = try makeSetup(in: dir)
            let document = try #require(setup.file.fileDocument)

            #expect(setup.manager.unsplit(setup.first))

            #expect(setup.file.fileDocument === document)
            #expect(setup.first.tabs.contains { $0.file == setup.file })
        }
    }
}
