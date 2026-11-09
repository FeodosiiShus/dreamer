import AppKit
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct EditorSplitActionsTests {
    @MainActor
    private struct Harness {
        let workspace: WorkspaceDocument
        let controller: DreamderWindowController
        let manager: EditorManager

        func close() {
            controller.window?.close()
            workspace.close()
        }
    }

    private func makeHarness(in directory: URL) throws -> Harness {
        try "let one = 1\n".write(to: directory.appending(path: "One.swift"), atomically: true, encoding: .utf8)
        let workspace = WorkspaceDocument()
        try workspace.read(from: directory, ofType: "")
        workspace.makeWindowControllers()
        let controller = try #require(workspace.windowControllers.first as? DreamderWindowController)
        controller.window?.isReleasedWhenClosed = false
        let manager = try #require(workspace.editorManager)
        let file = try #require(workspace.workspaceFileManager?.getFile(
            directory.appending(path: "One.swift").path(percentEncoded: false),
            createIfNotFound: true
        ))
        manager.openTab(item: file)
        return Harness(workspace: workspace, controller: controller, manager: manager)
    }

    @Test
    func splitActionsCreateUnsplitAndNavigateEditors() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            let original = harness.manager.activeEditor

            harness.controller.splitEditorRight(nil)
            #expect(harness.manager.flattenedEditors.count == 2)
            #expect(harness.manager.activeEditor !== original)
            #expect(harness.manager.activeEditor.selectedTab?.file.name == "One.swift")

            harness.controller.splitEditorDown(nil)
            #expect(harness.manager.flattenedEditors.count == 3)
            #expect(harness.manager.isInSplitter(harness.manager.activeEditor))

            let before = harness.manager.activeEditor
            harness.controller.gotoNextSplitter(nil)
            #expect(harness.manager.activeEditor !== before)
            harness.controller.gotoPreviousSplitter(nil)
            #expect(harness.manager.activeEditor === before)

            harness.controller.changeEditorSplitterOrientation(nil)
            harness.controller.unsplitEditor(nil)
            #expect(harness.manager.flattenedEditors.count == 2)

            harness.controller.unsplitAllEditors(nil)
            #expect(harness.manager.flattenedEditors.count == 1)
            #expect(harness.manager.isInSplitter(harness.manager.activeEditor) == false)
        }
    }
}
