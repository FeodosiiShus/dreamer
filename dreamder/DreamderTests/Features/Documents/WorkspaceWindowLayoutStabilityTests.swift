import AppKit
import OSLog
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized)
struct WorkspaceWindowLayoutStabilityTests {
    private struct Harness {
        let workspace: WorkspaceDocument
        let window: NSWindow
        let editorManager: EditorManager
        let start: Date

        func close() {
            window.close()
            workspace.close()
        }
    }

    private func makeHarness(in directory: URL) throws -> Harness {
        let longSource = (0..<1_500).map { "let value\($0) = \($0) // trailing comment that is long enough to exceed the pane width" }
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

    private func layoutLoopDiagnostics(since start: Date) throws -> [String] {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let position = store.position(date: start)
        let predicate = NSPredicate(format: "subsystem == %@", "com.apple.AppKit")
        return try store.getEntries(at: position, matching: predicate).compactMap { entry in
            guard let log = entry as? OSLogEntryLog else { return nil }
            let message = log.composedMessage
            let isLoopSignature = message.contains("has continued for")
                || message.contains("Update Constraints in Window passes")
                || message.contains("kept the layout or constraints dirty")
            return isLoopSignature ? message : nil
        }
    }

    private func expectSettled(_ harness: Harness, after step: String) async throws {
        try await Task.sleep(for: .milliseconds(1_200))
        harness.window.layoutIfNeeded()
        let diagnostics = try layoutLoopDiagnostics(since: harness.start)
        #expect(diagnostics.isEmpty, "AppKit reported a layout loop after \(step): \(diagnostics)")
    }

    @Test
    func splittingTheEditorTwiceLeavesTheWindowLayoutSettled() async throws {
        try await withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            try await expectSettled(harness, after: "initial layout")

            let right = harness.editorManager.splitActiveEditor(.trailing, workspace: harness.workspace)
            #expect(right != nil)
            try await expectSettled(harness, after: "split right")

            let down = harness.editorManager.splitActiveEditor(.bottom, workspace: harness.workspace)
            #expect(down != nil)
            try await expectSettled(harness, after: "split down")
            #expect(harness.editorManager.flattenedEditors.count == 3)
        }
    }

    @Test
    func closingSplitEditorsLeavesTheWindowLayoutSettled() async throws {
        try await withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            try await expectSettled(harness, after: "initial layout")

            let right = try #require(harness.editorManager.splitActiveEditor(.trailing, workspace: harness.workspace))
            try await expectSettled(harness, after: "split right")

            harness.editorManager.closeEditor(right)
            try await expectSettled(harness, after: "close split")
            #expect(harness.editorManager.flattenedEditors.count == 1)
        }
    }

    @Test
    func resizingTheWindowWithSplitsLeavesTheLayoutSettled() async throws {
        try await withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            harness.editorManager.splitActiveEditor(.trailing, workspace: harness.workspace)
            try await expectSettled(harness, after: "split right")

            harness.window.setContentSize(NSSize(width: 900, height: 600))
            try await expectSettled(harness, after: "shrink")
            harness.window.setContentSize(NSSize(width: 1500, height: 900))
            try await expectSettled(harness, after: "grow")
        }
    }
}
