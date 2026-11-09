import AppKit
import CodeEditSourceEditor
import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct DefinitionNavigatorJumpTests {
    @Test
    func jumpingOpensTheFileAtThePosition() throws {
        try withTempDir { directory in
            try "alpha\nbeta\n".write(to: directory.appending(path: "Target.swift"), atomically: true, encoding: .utf8)
            let workspace = try HostedSourceEditorFixture.registerWorkspace(at: directory)
            defer { workspace.close() }
            let url = directory.appending(path: "Target.swift")

            LSPDefinitionNavigator.jump(url: url, position: CursorPosition(line: 2, column: 3), in: workspace)

            let tab = workspace.editorManager?.activeEditor.selectedTab
            #expect(tab?.file.url.lastPathComponent == "Target.swift")
            #expect(tab?.cursorPositions.first?.start.line == 2)
            #expect(tab?.cursorPositions.first?.start.column == 3)
        }
    }

    @Test
    func jumpingFindsTheWorkspaceOfTheFileOrDoesNothing() throws {
        try withTempDir { directory in
            try "alpha\n".write(to: directory.appending(path: "Target.swift"), atomically: true, encoding: .utf8)
            let workspace = try HostedSourceEditorFixture.registerWorkspace(at: directory)
            defer { workspace.close() }

            LSPDefinitionNavigator.jump(
                url: URL(fileURLWithPath: "/nonexistent/dreamder/Elsewhere.swift"),
                position: CursorPosition(line: 1, column: 1)
            )
            #expect(workspace.editorManager?.activeEditor.selectedTab == nil)

            LSPDefinitionNavigator.jump(
                url: directory.appending(path: "Target.swift"),
                position: CursorPosition(line: 1, column: 2)
            )
            #expect(workspace.editorManager?.activeEditor.selectedTab?.cursorPositions.first?.start.column == 2)
        }
    }

    @Test
    func jumpingToADestinationUsesItsOneBasedPosition() throws {
        try withTempDir { directory in
            try "alpha\nbeta\n".write(to: directory.appending(path: "Target.swift"), atomically: true, encoding: .utf8)
            let workspace = try HostedSourceEditorFixture.registerWorkspace(at: directory)
            defer { workspace.close() }
            let url = directory.appending(path: "Target.swift")
            let destination = LSPNavigationDestination(
                uri: url.lspURI,
                fileURL: url,
                range: LSPRange(start: Position(line: 1, character: 2), end: Position(line: 1, character: 4))
            )

            LSPDefinitionNavigator.jump(to: destination, in: workspace)

            let cursor = workspace.editorManager?.activeEditor.selectedTab?.cursorPositions.first
            #expect(cursor?.start.line == 2)
            #expect(cursor?.start.column == 3)
        }
    }

    @Test
    func openingInAWorkspaceWithoutAnEditorManagerOpensNothing() throws {
        try withTempDir { directory in
            let workspace = WorkspaceDocument()
            defer { workspace.close() }
            let manager = workspace.editorManager
            workspace.editorManager = nil

            LSPDefinitionNavigator.open(
                url: directory.appending(path: "Target.swift"),
                position: CursorPosition(line: 1, column: 1),
                in: workspace
            )

            #expect(manager?.activeEditor.tabs.isEmpty == true)
        }
    }

    @Test
    func aFileOutsideTheIndexedWorkspaceTreeStillOpensAtThePosition() throws {
        try withTempDir { directory in
            let url = directory.appending(path: "Loose.swift")
            try "alpha\nbeta\n".write(to: url, atomically: true, encoding: .utf8)
            let workspace = WorkspaceDocument()
            defer { workspace.close() }

            LSPDefinitionNavigator.open(url: url, position: CursorPosition(line: 2, column: 4), in: workspace)

            let tab = workspace.editorManager?.activeEditor.selectedTab
            #expect(tab?.file.url.lastPathComponent == "Loose.swift")
            #expect(tab?.cursorPositions.first?.start.line == 2)
            #expect(tab?.cursorPositions.first?.start.column == 4)
        }
    }
}
