import AppKit
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct FindNavigatorOpenerTests {
    private func matchInFirstResult(of workspace: WorkspaceDocument, named name: String) throws -> SearchResultMatchModel {
        let state = try #require(workspace.searchState)
        let result = try #require(state.searchResult.first { $0.file.name == name })
        return try #require(result.lineMatches.first)
    }

    @Test
    func resolveReturnsTheWorkspaceManagersFileAndFallsBackToTheGivenOne() async throws {
        try await withTempDir { dir in
            let workspace = try await FindNavigatorTestWorkspace.searched(in: dir)
            defer { workspace.close() }
            let file = CEWorkspaceFile(url: dir.appending(path: "a.swift"))

            let resolved = FindNavigatorOpener.resolve(file, in: workspace)
            #expect(resolved.url.standardizedFileURL == file.url.standardizedFileURL)

            workspace.workspaceFileManager = nil
            #expect(FindNavigatorOpener.resolve(file, in: workspace) === file)
        }
    }

    @Test
    func openingAFileSelectsItsTabInTheActiveEditor() async throws {
        try await withTempDir { dir in
            let workspace = try await FindNavigatorTestWorkspace.searched(in: dir)
            defer { workspace.close() }
            let editor = try #require(workspace.editorManager?.activeEditor)
            let file = CEWorkspaceFile(url: dir.appending(path: "b.txt"))

            FindNavigatorOpener.open(file, in: workspace)

            #expect(editor.tabs.count == 1)
            #expect(editor.selectedTab?.file.url.standardizedFileURL == file.url.standardizedFileURL)
        }
    }

    @Test
    func openingWithoutAnEditorManagerDoesNothing() async throws {
        try await withTempDir { dir in
            let workspace = try await FindNavigatorTestWorkspace.searched(in: dir)
            defer { workspace.close() }
            let match = try matchInFirstResult(of: workspace, named: "a.swift")
            let file = match.file
            workspace.editorManager = nil

            FindNavigatorOpener.open(file, in: workspace)
            FindNavigatorOpener.open(match, in: workspace)

            #expect(workspace.editorManager == nil)
        }
    }

    @Test
    func openingAMatchPlacesTheSelectionOnItsUsage() async throws {
        try await withTempDir { dir in
            let workspace = try await FindNavigatorTestWorkspace.searched(in: dir)
            defer { workspace.close() }
            let editor = try #require(workspace.editorManager?.activeEditor)
            let match = try matchInFirstResult(of: workspace, named: "a.swift")
            let usage = try #require(match.usage)

            FindNavigatorOpener.open(match, in: workspace)

            #expect(editor.selectedTab?.file.url.standardizedFileURL == match.file.url.standardizedFileURL)
            let selected = try #require(editor.selectedTab?.cursorPositions.first)
            #expect(selected.start.line == usage.start.line)
            #expect(selected.start.column == usage.start.column)
            #expect(selected.end?.line == usage.end.line)
            #expect(selected.end?.column == usage.end.column)
            let target = match.file.url.standardizedFileURL
            let stored = try #require(editor.tabs.first { $0.file.url.standardizedFileURL == target })
            #expect(stored.cursorPositions.first?.start.column == usage.start.column)
        }
    }

    @Test
    func openingAMatchWithoutAUsageOnlyOpensTheFile() async throws {
        try await withTempDir { dir in
            let workspace = try await FindNavigatorTestWorkspace.searched(in: dir)
            defer { workspace.close() }
            let editor = try #require(workspace.editorManager?.activeEditor)
            let match = try matchInFirstResult(of: workspace, named: "b.txt")
            FindNavigatorOpener.open(match.file, in: workspace)
            let before = try #require(editor.selectedTab?.cursorPositions.map { [$0.start.line, $0.start.column] })
            match.usage = nil

            FindNavigatorOpener.open(match, in: workspace)

            #expect(editor.selectedTab?.file.url.standardizedFileURL == match.file.url.standardizedFileURL)
            #expect(editor.selectedTab?.cursorPositions.map { [$0.start.line, $0.start.column] } == before)
        }
    }

    @Test
    func focusEditorMovesFirstResponderToTheActiveTabsTextView() async throws {
        try await withTempDir { dir in
            let workspace = try await FindNavigatorTestWorkspace.searched(in: dir)
            defer { workspace.close() }
            let fixture = try HostedSourceEditorFixture.make(
                in: dir,
                fileName: "Focus.txt",
                typeIdentifier: "public.plain-text",
                contents: "alpha needle\n"
            )
            let hosted = fixture.host(
                coordinators: [fixture.document.contentCoordinator, fixture.document.textViewBinder],
                size: NSSize(width: 900, height: 600)
            )
            defer { hosted.close() }
            try await eventually { fixture.document.attachedTextView != nil }
            let textView = try #require(fixture.document.attachedTextView)
            let editor = try #require(workspace.editorManager?.activeEditor)
            FindNavigatorOpener.open(CEWorkspaceFile(url: dir.appending(path: "b.txt")), in: workspace)
            editor.selectedTab?.file.fileDocument = fixture.document
            hosted.window.makeFirstResponder(nil)
            #expect(hosted.window.firstResponder !== textView)

            await FindNavigatorOpener.focusEditor(in: workspace)

            #expect(hosted.window.firstResponder === textView)
        }
    }

    @Test
    func focusEditorGivesUpWhenNoTextViewIsAttached() async throws {
        try await withTempDir { dir in
            let workspace = try await FindNavigatorTestWorkspace.searched(in: dir)
            defer { workspace.close() }
            #expect(workspace.editorManager?.activeEditor.selectedTab == nil)

            await FindNavigatorOpener.focusEditor(in: workspace)

            #expect(workspace.editorManager?.activeEditor.selectedTab == nil)
        }
    }
}
