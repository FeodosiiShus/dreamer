import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct DreamderWindowControllerEditorSplitsCoverageTests {
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
    func splittingRightPlacesTheNewEditorNextToTheOriginalOnAHorizontalAxis() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }

            harness.controller.splitEditorRight(nil)

            #expect(harness.manager.flattenedEditors.count == 2)
            #expect(harness.manager.activeEditor.parent?.axis == .horizontal)
        }
    }

    @Test
    func splittingDownStacksTheNewEditorOnAVerticalAxis() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }

            harness.controller.splitEditorDown(nil)

            #expect(harness.manager.flattenedEditors.count == 2)
            #expect(harness.manager.activeEditor.parent?.axis == .vertical)
        }
    }

    @Test
    func changingTheSplitterOrientationFlipsTheAxisAndBackAgain() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            harness.controller.splitEditorRight(nil)

            harness.controller.changeEditorSplitterOrientation(nil)
            #expect(harness.manager.activeEditor.parent?.axis == .vertical)

            harness.controller.changeEditorSplitterOrientation(nil)
            #expect(harness.manager.activeEditor.parent?.axis == .horizontal)
        }
    }

    @Test
    func navigatingBetweenSplitsCyclesThroughEveryEditor() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            harness.controller.splitEditorRight(nil)
            harness.controller.splitEditorDown(nil)
            let editors = harness.manager.flattenedEditors
            #expect(editors.count == 3)
            let start = harness.manager.activeEditor

            var visited: [Editor] = []
            for _ in editors {
                harness.controller.gotoNextSplitter(nil)
                visited.append(harness.manager.activeEditor)
            }

            #expect(harness.manager.activeEditor === start)
            #expect(visited.count == 3)
            #expect(editors.allSatisfy { editor in visited.contains { $0 === editor } })

            harness.controller.gotoPreviousSplitter(nil)
            harness.controller.gotoNextSplitter(nil)
            #expect(harness.manager.activeEditor === start)
        }
    }

    @Test
    func unsplittingRemovesOneEditorAndUnsplitAllRemovesEverySplit() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            harness.controller.splitEditorRight(nil)
            harness.controller.splitEditorDown(nil)

            harness.controller.unsplitEditor(nil)
            #expect(harness.manager.flattenedEditors.count == 2)

            harness.controller.unsplitAllEditors(nil)
            #expect(harness.manager.flattenedEditors.count == 1)
            #expect(!harness.manager.isInSplitter(harness.manager.activeEditor))
        }
    }

    @Test
    func splitActionsOnASingleEditorChangeNothingExceptTheCyclingNoOps() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            let only = harness.manager.activeEditor

            harness.controller.unsplitEditor(nil)
            harness.controller.unsplitAllEditors(nil)
            harness.controller.changeEditorSplitterOrientation(nil)
            harness.controller.gotoNextSplitter(nil)
            harness.controller.gotoPreviousSplitter(nil)

            #expect(harness.manager.flattenedEditors.count == 1)
            #expect(harness.manager.activeEditor === only)
        }
    }

    @Test
    func splitActionsNeedAWorkspace() {
        let window = NSWindow()
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let controller = DreamderWindowController(window: window, workspace: nil)

        controller.splitEditorRight(nil)
        controller.splitEditorDown(nil)
        controller.unsplitEditor(nil)
        controller.unsplitAllEditors(nil)
        controller.changeEditorSplitterOrientation(nil)
        controller.gotoNextSplitter(nil)
        controller.gotoPreviousSplitter(nil)

        #expect(controller.workspace == nil)
    }
}
