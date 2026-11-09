import CodeEditSourceEditor
import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct EditorLocationNavigationTests {
    private func write(_ name: String, in dir: URL) throws -> URL {
        let url = dir.appending(path: name)
        try "one\ntwo\nthree\n".write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test
    func opensTheFileInATabAndMovesTheCaret() async throws {
        try withTempDir { dir in
            let url = try write("A.swift", in: dir)
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }

            EditorLocationNavigation.open(fileURL: url, line: 3, column: 2, workspace: workspace)

            let editorManager = try #require(workspace.editorManager)
            let editor = editorManager.activeEditor
            let tab = try #require(editor.selectedTab)
            #expect(editor.tabs.count == 1)
            #expect(tab.file.url.standardizedFileURL == url.standardizedFileURL)
            #expect(tab.cursorPositions.count == 1)
            #expect(tab.cursorPositions.first?.start.line == 3)
            #expect(tab.cursorPositions.first?.start.column == 2)
        }
    }

    @Test
    func navigatingAgainMovesTheCaretOfTheExistingTab() async throws {
        try withTempDir { dir in
            let url = try write("A.swift", in: dir)
            let other = try write("B.swift", in: dir)
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }

            EditorLocationNavigation.open(fileURL: url, line: 2, column: 1, workspace: workspace)
            EditorLocationNavigation.open(fileURL: other, line: 1, column: 1, workspace: workspace)
            EditorLocationNavigation.open(fileURL: url, line: 3, column: 4, workspace: workspace)

            let editor = try #require(workspace.editorManager).activeEditor
            let tab = try #require(editor.selectedTab)
            #expect(editor.tabs.count == 2)
            #expect(tab.file.url.standardizedFileURL == url.standardizedFileURL)
            #expect(tab.cursorPositions.first?.start.line == 3)
            #expect(tab.cursorPositions.first?.start.column == 4)
        }
    }

    @Test
    func nonPositiveLinesAndColumnsClampToTheDocumentStart() async throws {
        try withTempDir { dir in
            let url = try write("A.swift", in: dir)
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }

            EditorLocationNavigation.open(fileURL: url, line: 0, column: -4, workspace: workspace)

            let editorManager = try #require(workspace.editorManager)
            let tab = try #require(editorManager.activeEditor.selectedTab)
            #expect(tab.cursorPositions.first?.start.line == 1)
            #expect(tab.cursorPositions.first?.start.column == 1)
        }
    }

    @Test
    func filesOutsideTheWorkspaceTreeAreStillOpened() async throws {
        try withTempDir { dir in
            let url = try write("A.swift", in: dir)
            let workspace = WorkspaceDocument()
            #expect(workspace.workspaceFileManager == nil)

            EditorLocationNavigation.open(fileURL: url, line: 2, column: 3, workspace: workspace)

            let editor = try #require(workspace.editorManager).activeEditor
            let tab = try #require(editor.selectedTab)
            #expect(tab.file.url.standardizedFileURL == url.standardizedFileURL)
            #expect(tab.cursorPositions.first?.start.line == 2)
            #expect(tab.cursorPositions.first?.start.column == 3)
        }
    }

    @Test
    func aClosedWorkspaceIgnoresTheRequest() async throws {
        try withTempDir { dir in
            let url = try write("A.swift", in: dir)
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            workspace.close()
            #expect(workspace.editorManager == nil)

            EditorLocationNavigation.open(fileURL: url, line: 1, column: 1, workspace: workspace)

            #expect(workspace.editorManager == nil)
        }
    }
}
