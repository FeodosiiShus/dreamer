import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
struct EditorTabsCoverageHarness {
    let workspace: WorkspaceDocument
    let manager: EditorManager
    let editor: Editor
    let files: [CEWorkspaceFile]
    let directory: URL

    static func make(in directory: URL, names: [String]) throws -> EditorTabsCoverageHarness {
        for name in names {
            try "let value = 1\n".write(
                to: directory.appending(path: name),
                atomically: true,
                encoding: .utf8
            )
        }
        let workspace = try HostedViewFixture.makeWorkspace(in: directory)
        let manager = try #require(workspace.editorManager)
        var files: [CEWorkspaceFile] = []
        for name in names {
            let file = try #require(workspace.workspaceFileManager?.getFile(
                directory.appending(path: name).path(percentEncoded: false),
                createIfNotFound: true
            ))
            manager.openTab(item: file)
            files.append(file)
        }
        return EditorTabsCoverageHarness(
            workspace: workspace,
            manager: manager,
            editor: manager.activeEditor,
            files: files,
            directory: directory
        )
    }

    func file(_ name: String) throws -> CEWorkspaceFile {
        try #require(files.first { $0.name == name })
    }

    func context(_ file: CEWorkspaceFile) -> EditorTabContext {
        EditorTabContext(file: file, editor: editor, editorManager: manager, workspace: workspace)
    }

    func host<Content: View>(
        size: NSSize,
        active: Bool = true,
        focused: Bool = true,
        @ViewBuilder _ content: () -> Content
    ) throws -> HostedView {
        let tabEditor = editor
        let view = content()
        return try HostedViewFixture.hostInWorkspace(workspace, size: size) {
            view
                .environment(tabEditor)
                .environment(\.isActiveEditor, active)
                .environment(\.controlActiveState, focused ? .key : .inactive)
        }
    }

    func close() {
        workspace.close()
    }
}

@MainActor
@Observable
final class EditorTabsCoverageFlags {
    var gestureActive = false
    var hovering = false
    var closed = 0
}
