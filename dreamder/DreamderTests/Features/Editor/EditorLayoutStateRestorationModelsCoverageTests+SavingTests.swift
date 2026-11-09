import AppKit
import Foundation
import OrderedCollections
import Testing
@testable import Dreamder

@MainActor
extension EditorLayoutStateRestorationModelsCoverageTests {
    @Test
    func restoreWithoutAFileManagerKeepsTheDecodedLayout() throws {
        try withTempDir { dir in
            let workspace = WorkspaceDocument()
            workspace.fileURL = dir
            defer { discardState(of: workspace) }
            let first = Editor(files: OrderedSet([CEWorkspaceFile(url: dir.appending(path: "one.txt"))]))
            let second = Editor(files: OrderedSet([CEWorkspaceFile(url: dir.appending(path: "two.txt"))]))
            let source = EditorManager()
            source.editorLayout = .horizontal(SplitViewData(.horizontal, editorLayouts: [.one(first), .one(second)]))
            source.activeEditor = second
            source.saveRestorationState(workspace)

            let restored = EditorManager()
            restored.restoreFromState(workspace)

            let editors = restored.flattenedEditors
            #expect(editors.map(\.id) == [first.id, second.id])
            #expect(editors.map { $0.tabs.map { $0.file.url.lastPathComponent } } == [["one.txt"], ["two.txt"]])
            #expect(restored.activeEditor === editors[1])
            #expect(editors.allSatisfy { $0.workspace === workspace })
        }
    }

    @Test
    func restoreWithoutSavedStateOnlyAttachesTheWorkspace() throws {
        try withTempDir { dir in
            let workspace = WorkspaceDocument()
            workspace.fileURL = dir
            defer { discardState(of: workspace) }
            let manager = EditorManager()
            let before = manager.activeEditor

            manager.restoreFromState(workspace)

            #expect(manager.activeEditor === before)
            #expect(before.workspace === workspace)
        }
    }

    @Test
    func aFailingEncoderClearsThePreviouslySavedState() throws {
        try withTempDir { dir in
            let workspace = WorkspaceDocument()
            workspace.fileURL = dir
            defer { discardState(of: workspace) }
            let manager = EditorManager()
            manager.saveRestorationState(workspace)
            #expect(workspace.getFromWorkspaceState(.openTabs) is Data)

            manager.saveRestorationState(workspace) { _ in throw ForcedFailure() }

            #expect(workspace.getFromWorkspaceState(.openTabs) == nil)
        }
    }
}
