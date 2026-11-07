import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite
struct GitBlameCoordinatorRegistryTests {
    private func makeEditor(_ name: String = "file.swift") -> EditorInstance {
        EditorInstance(workspace: nil, file: CEWorkspaceFile(url: URL(filePath: "/fake/dir/\(name)")))
    }

    @Test
    func lookupReturnsTheCoordinatorOfThatEditorInstance() {
        let editor = makeEditor()
        let coordinator = GitBlameCoordinator(editorInstance: editor, codeFile: CodeFileDocument())

        #expect(GitBlameCoordinator.coordinator(for: editor) === coordinator)
    }

    @Test
    func lookupForAnotherEditorInstanceIsNil() {
        let registered = makeEditor("a.swift")
        let other = makeEditor("b.swift")
        let coordinator = GitBlameCoordinator(editorInstance: registered, codeFile: CodeFileDocument())

        #expect(GitBlameCoordinator.coordinator(for: other) == nil)
        #expect(GitBlameCoordinator.coordinator(for: registered) === coordinator)
    }

    @Test
    func destroyRemovesTheEntry() {
        let editor = makeEditor()
        let coordinator = GitBlameCoordinator(editorInstance: editor, codeFile: CodeFileDocument())

        coordinator.destroy()

        #expect(GitBlameCoordinator.coordinator(for: editor) == nil)
    }

    @Test
    func releasedCoordinatorIsNotReturned() {
        let editor = makeEditor()
        var coordinator: GitBlameCoordinator? = GitBlameCoordinator(editorInstance: editor, codeFile: CodeFileDocument())
        #expect(GitBlameCoordinator.coordinator(for: editor) != nil)

        coordinator = nil

        #expect(coordinator == nil)
        #expect(GitBlameCoordinator.coordinator(for: editor) == nil)
    }

    @Test
    func newerCoordinatorForTheSameEditorReplacesTheOlderOne() {
        let editor = makeEditor()
        let document = CodeFileDocument()
        let older = GitBlameCoordinator(editorInstance: editor, codeFile: document)
        let newer = GitBlameCoordinator(editorInstance: editor, codeFile: document)

        #expect(GitBlameCoordinator.coordinator(for: editor) === newer)
        older.destroy()
        #expect(GitBlameCoordinator.coordinator(for: editor) === newer)
    }
}
