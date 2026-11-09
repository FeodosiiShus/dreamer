import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct ProjectNavigatorRepresentableTests {
    typealias Harness = ProjectNavigatorControllerHarness
    typealias Coordinator = ProjectNavigatorOutlineView.Coordinator

    @Test
    func hostedNavigatorFollowsSelectionHighlightAndFilterChanges() async throws {
        try await withTempDir { directory in
            for name in ["Sources/main.swift", "a.txt", "b.md"] {
                let url = directory.appending(path: name)
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try "content\n".write(to: url, atomically: true, encoding: .utf8)
            }
            let workspace = try HostedViewFixture.makeWorkspace(in: directory)
            defer { workspace.close() }
            let editor = try #require(workspace.editorManager?.activeEditor)
            editor.workspace = workspace
            let reference = ProjectNavigatorControllerReference()
            let hosted = try HostedViewFixture.hostInWorkspace(workspace) {
                ProjectNavigatorOutlineView(controllerReference: reference)
            }
            defer { hosted.close() }
            try await hosted.settle()
            let controller = try #require(reference.controller)
            let manager = try #require(workspace.workspaceFileManager)
            defer {
                if let name = controller.outlineView.autosaveName {
                    UserDefaults.standard.removeObject(forKey: "NSOutlineView Items \(name)")
                }
            }
            let a = try #require(manager.getFile(directory.appending(path: "a.txt").path, createIfNotFound: true))
            let b = try #require(manager.getFile(directory.appending(path: "b.md").path, createIfNotFound: true))

            #expect(controller.workspace === workspace)
            #expect(controller.editor === editor)
            #expect(controller.outlineView.numberOfRows > 1)

            editor.openTab(file: a, asTemporary: false)
            try await eventually { controller.outlineView.selectedRow == controller.outlineView.row(forItem: a) }

            workspace.listenerModel.highlightedFileItem = b
            try await eventually { controller.outlineView.selectedRow == controller.outlineView.row(forItem: b) }

            workspace.navigatorFilter = "a"
            try await Task.sleep(for: .milliseconds(20))
            workspace.navigatorFilter = "zzz-no-such-file"
            try await eventually { !controller.noResultsLabel.isHidden }

            workspace.navigatorFilter = ""
            try await eventually { controller.outlineView.autosaveExpandedItems }

            workspace.sortFoldersOnTop = false
            workspace.sourceControlFilter = true
            workspace.sourceControlFilter = false
            try await eventually { controller.outlineView.autosaveExpandedItems }
        }
    }

    @Test
    func fileManagerUpdatesReloadTheOutlineAndKeepTheSelection() async throws {
        try await Harness.run(folders: ["Sources"], files: ["a.txt", "b.md", "Sources/main.swift"]) { harness in
            var coordinator: Coordinator? = Coordinator(harness.workspace)
            coordinator?.controller = harness.controller
            let a = try harness.file("a.txt")
            harness.select([a])
            try harness.write("c.txt")

            coordinator?.fileManagerUpdated(updatedItems: [harness.rootFile])

            #expect(harness.outlineView.selectedRow == harness.row(of: a))
            #expect(harness.controller.shouldSendSelectionUpdate)
            #expect(!harness.controller.shouldReloadAfterDoneEditing)

            coordinator?.controller = nil
            coordinator?.fileManagerUpdated(updatedItems: [harness.rootFile])
            coordinator = nil
        }
    }

    @Test
    func fileManagerUpdatesAreDeferredWhileAFieldInsideTheOutlineIsEdited() async throws {
        try await Harness.run(folders: ["Sources"], files: ["a.txt", "b.md", "Sources/main.swift"]) { harness in
            let coordinator = Coordinator(harness.workspace)
            coordinator.controller = harness.controller
            let field = NSTextField(string: "editing")
            field.frame = NSRect(x: 0, y: 0, width: 100, height: 20)
            harness.outlineView.addSubview(field)
            #expect(harness.window.makeFirstResponder(field))
            #expect(harness.window.firstResponder is NSTextView)

            coordinator.fileManagerUpdated(updatedItems: [harness.rootFile])

            #expect(harness.controller.shouldReloadAfterDoneEditing)

            #expect(harness.window.makeFirstResponder(harness.outlineView))
            harness.controller.cellDidFinishEditing()
            field.removeFromSuperview()
        }
    }

    @Test
    func fileManagerUpdatesStillReloadWhenAnOutsideFieldIsEdited() async throws {
        try await Harness.run(folders: ["Sources"], files: ["a.txt", "Sources/main.swift"]) { harness in
            let coordinator = Coordinator(harness.workspace)
            coordinator.controller = harness.controller
            let field = NSTextField(string: "outside")
            field.frame = NSRect(x: 0, y: 0, width: 100, height: 20)
            harness.window.contentView?.addSubview(field)
            #expect(harness.window.makeFirstResponder(field))

            coordinator.fileManagerUpdated(updatedItems: [harness.rootFile])

            #expect(!harness.controller.shouldReloadAfterDoneEditing)
            #expect(harness.window.makeFirstResponder(harness.outlineView))
            field.removeFromSuperview()
        }
    }

    @Test
    func theControllerReferenceHoldsTheControllerWeakly() async throws {
        let reference = ProjectNavigatorControllerReference()
        #expect(reference.controller == nil)
    }
}
