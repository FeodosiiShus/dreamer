import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct EditorInstanceModelsCoverageTests {
    private func makeInstance(in directory: URL, workspace: WorkspaceDocument?) -> EditorInstance {
        EditorInstance(workspace: workspace, file: CEWorkspaceFile(url: directory.appending(path: "a.txt")))
    }

    @Test
    func findTextFollowsTheWorkspaceSearchQuery() async throws {
        try await withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            let search = try #require(workspace.searchState)
            let instance = makeInstance(in: dir, workspace: workspace)

            search.searchQuery = "needle"

            try await eventually { instance.findText == "needle" }
            #expect(search.searchQuery == "needle")
        }
    }

    @Test
    func typingFindTextUpdatesTheWorkspaceSearchQuery() async throws {
        try await withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            let search = try #require(workspace.searchState)
            let instance = makeInstance(in: dir, workspace: workspace)
            search.searchQuery = "seed"
            try await eventually { instance.findText == "seed" }

            instance.findText = "typed"

            try await eventually { search.searchQuery == "typed" }
            #expect(instance.findText == "typed")
        }
    }

    @Test
    func clearingFindTextRestoresTheWorkspaceSearchQuery() async throws {
        try await withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            let search = try #require(workspace.searchState)
            let instance = makeInstance(in: dir, workspace: workspace)
            search.searchQuery = "kept"
            try await eventually { instance.findText == "kept" }

            instance.findText = nil

            try await eventually { instance.findText == "kept" }
            #expect(search.searchQuery == "kept")
        }
    }

    @Test
    func replaceTextFollowsTheWorkspaceReplacement() async throws {
        try await withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            let search = try #require(workspace.searchState)
            let instance = makeInstance(in: dir, workspace: workspace)

            search.replaceText = "swap"

            try await eventually { instance.replaceText == "swap" }
            #expect(search.replaceText == "swap")
        }
    }

    @Test
    func typingReplaceTextUpdatesTheWorkspaceReplacement() async throws {
        try await withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            let search = try #require(workspace.searchState)
            let instance = makeInstance(in: dir, workspace: workspace)
            search.replaceText = "seed"
            try await eventually { instance.replaceText == "seed" }

            instance.replaceText = "typed"

            try await eventually { search.replaceText == "typed" }
            #expect(instance.replaceText == "typed")
        }
    }

    @Test
    func clearingReplaceTextRestoresTheWorkspaceReplacement() async throws {
        try await withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            let search = try #require(workspace.searchState)
            let instance = makeInstance(in: dir, workspace: workspace)
            search.replaceText = "kept"
            try await eventually { instance.replaceText == "kept" }

            instance.replaceText = nil

            try await eventually { instance.replaceText == "kept" }
            #expect(search.replaceText == "kept")
        }
    }

    @Test
    func newInstancesStartWithTheWorkspaceSearchValues() async throws {
        try withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            let search = try #require(workspace.searchState)
            search.searchQuery = "query"
            search.replaceText = "replacement"

            let instance = makeInstance(in: dir, workspace: workspace)

            #expect(instance.findText == "query")
            #expect(instance.replaceText == "replacement")
        }
    }

    @Test
    func cursorAndScrollStateArePersistedAndRestored() async throws {
        try await withTempDir { dir in
            let restoration = try #require(EditorStateRestoration.shared)
            let url = dir.appending(path: "a.txt")
            let instance = makeInstance(in: dir, workspace: nil)

            instance.cursorPositions = [CursorPosition(range: NSRange(location: 3, length: 2))]
            instance.scrollPosition = CGPoint(x: 0, y: 40)

            try await eventually { restoration.restorationState(for: url)?.cursorPositions == [3..<5] }
            try await eventually { restoration.restorationState(for: url)?.scrollPositionY == 40 }

            let restored = makeInstance(in: dir, workspace: nil)
            #expect(restored.cursorPositions.map(\.range) == [NSRange(location: 3, length: 2)])
            #expect(restored.scrollPosition == CGPoint(x: 0, y: 40))
            #expect(restored.requestedScrollPosition == CGPoint(x: 0, y: 40))
        }
    }

    @Test
    func revertedEditsInOneTurnAreNotPersisted() async throws {
        try await withTempDir { dir in
            let restoration = try #require(EditorStateRestoration.shared)
            let url = dir.appending(path: "a.txt")
            let instance = makeInstance(in: dir, workspace: nil)
            try await eventually { restoration.restorationState(for: url) != nil }

            for _ in 0..<5 {
                instance.scrollPosition = CGPoint(x: 5, y: 5)
                instance.scrollPosition = nil
                try await Task.sleep(for: .milliseconds(30))
            }

            try await eventually { restoration.restorationState(for: url)?.scrollPosition == .zero }
            #expect(instance.scrollPosition == nil)
        }
    }

    @Test
    func instancesAreIdentifiedByTheirFile() {
        let first = EditorInstance(workspace: nil, file: CEWorkspaceFile(url: URL(filePath: "/fake/one.txt")))
        let same = EditorInstance(workspace: nil, file: CEWorkspaceFile(url: URL(filePath: "/fake/one.txt")))
        let other = EditorInstance(workspace: nil, file: CEWorkspaceFile(url: URL(filePath: "/fake/two.txt")))

        #expect(first == same)
        #expect(first != other)
        #expect(first.hashValue == same.hashValue)
        #expect(Set([first, same, other]).count == 2)
    }

    @Test
    func detachedRangeTranslatorDoesNothing() {
        let translator = EditorInstance.RangeTranslator()

        #expect(translator.linesInRange(NSRange(location: 0, length: 3)) == 0)
        translator.moveLinesUp()
        translator.moveLinesDown()
        translator.destroy()
        #expect(translator.linesInRange(NSRange(location: 0, length: 0)) == 0)
    }

    @Test
    func rangeTranslatorCountsLinesAndMovesThemInAHostedEditor() async throws {
        try await withTempDir { dir in
            let fixture = try HostedSourceEditorFixture.make(
                in: dir,
                fileName: "Lines.txt",
                typeIdentifier: "public.plain-text",
                contents: "alpha\nbravo\ncharlie\n"
            )
            let translator = fixture.editorInstance.rangeTranslator
            let hosted = fixture.host(
                coordinators: [fixture.document.contentCoordinator, translator],
                size: NSSize(width: 900, height: 600)
            )
            defer { hosted.close() }
            try await eventually { hosted.controller?.textView?.window === hosted.window }
            let controller = try #require(hosted.controller)
            controller.textView.isEditable = true

            try await eventually { translator.linesInRange(NSRange(location: 0, length: 14)) == 3 }
            #expect(translator.linesInRange(NSRange(location: 0, length: 5)) == 1)
            #expect(translator.linesInRange(NSRange(location: 0, length: 8)) == 2)

            let firstCursor = NSRange(location: 1, length: 0)
            controller.setCursorPositions([CursorPosition(range: firstCursor)], scrollToVisible: false)
            try await eventually { controller.cursorPositions.map(\.range) == [firstCursor] }
            translator.moveLinesDown()
            #expect(controller.textView.string == "bravo\nalpha\ncharlie\n")

            let secondCursor = NSRange(location: 13, length: 0)
            controller.setCursorPositions([CursorPosition(range: secondCursor)], scrollToVisible: false)
            try await eventually { controller.cursorPositions.map(\.range) == [secondCursor] }
            translator.moveLinesUp()
            #expect(controller.textView.string == "bravo\ncharlie\nalpha\n")
        }
    }
}
