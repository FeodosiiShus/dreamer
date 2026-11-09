import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct WorkspaceWindowLayoutStabilityTests {
    @MainActor
    private final class Harness {
        let workspace: WorkspaceDocument
        let window: NSWindow
        let editorManager: EditorManager
        let start: Date
        private(set) var steps: [(date: Date, name: String)] = []

        init(workspace: WorkspaceDocument, window: NSWindow, editorManager: EditorManager, start: Date) {
            self.workspace = workspace
            self.window = window
            self.editorManager = editorManager
            self.start = start
        }

        func record(_ step: String) {
            steps.append((Date(), step))
        }

        func close() {
            window.close()
            workspace.close()
        }
    }

    private func makeHarness(in directory: URL) throws -> Harness {
        let longSource = (0..<300).map { "let value\($0) = \($0) // trailing comment that is long enough to exceed the pane width" }
            .joined(separator: "\n")
        try longSource.write(
            to: directory.appending(path: "Model.swift"),
            atomically: true,
            encoding: .utf8
        )
        let start = Date()
        let workspace = WorkspaceDocument()
        try workspace.read(from: directory, ofType: "")
        workspace.makeWindowControllers()
        let window = try #require(workspace.windowControllers.first?.window)
        window.isReleasedWhenClosed = false
        window.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: true)
        let editorManager = try #require(workspace.editorManager)
        let file = try #require(workspace.workspaceFileManager?.getFile(
            directory.appending(path: "Model.swift").path(percentEncoded: false),
            createIfNotFound: true
        ))
        editorManager.openTab(item: file)
        workspace.toolWindowManager.show(.project)
        workspace.toolWindowManager.show(.terminal)
        return Harness(workspace: workspace, window: window, editorManager: editorManager, start: start)
    }

    private func settle(_ harness: Harness, after step: String) async throws {
        harness.record(step)
        try await Task.sleep(for: .milliseconds(1_200))
        harness.window.layoutIfNeeded()
    }

    private func expectNoLayoutLoop(_ harness: Harness) async throws {
        let diagnostics = try await AppKitLayoutLoopDetector.diagnostics(since: harness.start)
        #expect(diagnostics.isEmpty, "\(AppKitLayoutLoopDetector.describe(diagnostics, steps: harness.steps))")
    }

    @Test
    func splittingTheEditorTwiceLeavesTheWindowLayoutSettled() async throws {
        try await withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            try await settle(harness, after: "initial layout")

            let right = harness.editorManager.splitActiveEditor(.trailing, workspace: harness.workspace)
            #expect(right != nil)
            try await settle(harness, after: "split right")

            let down = harness.editorManager.splitActiveEditor(.bottom, workspace: harness.workspace)
            #expect(down != nil)
            try await settle(harness, after: "split down")
            #expect(harness.editorManager.flattenedEditors.count == 3)
            try await expectNoLayoutLoop(harness)
        }
    }

    @Test
    func closingSplitEditorsLeavesTheWindowLayoutSettled() async throws {
        try await withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            try await settle(harness, after: "initial layout")

            let right = try #require(harness.editorManager.splitActiveEditor(.trailing, workspace: harness.workspace))
            try await settle(harness, after: "split right")

            harness.editorManager.closeEditor(right)
            try await settle(harness, after: "close split")
            #expect(harness.editorManager.flattenedEditors.count == 1)
            try await expectNoLayoutLoop(harness)
        }
    }

    @Test
    func resizingTheWindowWithSplitsLeavesTheLayoutSettled() async throws {
        try await withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            harness.editorManager.splitActiveEditor(.trailing, workspace: harness.workspace)
            try await settle(harness, after: "split right")

            harness.window.setContentSize(NSSize(width: 900, height: 600))
            try await settle(harness, after: "shrink")
            harness.window.setContentSize(NSSize(width: 1500, height: 900))
            try await settle(harness, after: "grow")
            try await expectNoLayoutLoop(harness)
        }
    }
}
