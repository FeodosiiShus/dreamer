import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct DreamderWindowControllerMarkdownCoverageTests {
    static let gridCellCenter = CGPoint(
        x: (MarkdownTableGridPicker.cellSize + MarkdownTableGridPicker.cellSpacing) * 1.5,
        y: (MarkdownTableGridPicker.cellSize + MarkdownTableGridPicker.cellSpacing) * 1.5
    )

    @MainActor
    struct Harness {
        let workspace: WorkspaceDocument
        let controller: DreamderWindowController
        let window: NSWindow
        let codeFile: CodeFileDocument
        let editorInstance: EditorInstance

        var text: String {
            codeFile.content?.string ?? ""
        }

        var cursorRanges: [NSRange] {
            editorInstance.cursorPositions.map(\.range)
        }

        func select(_ ranges: [NSRange]) {
            editorInstance.cursorPositions = ranges.map { CursorPosition(range: $0) }
        }

        func focusedTextView() throws -> TextView {
            let storage = try #require(codeFile.content)
            let textView = TextView(string: "")
            textView.setTextStorage(storage)
            textView.frame = NSRect(x: 0, y: 0, width: 400, height: 200)
            window.contentView?.addSubview(textView)
            try #require(textView.textStorage === storage)
            try #require(window.makeFirstResponder(textView))
            return textView
        }

        func close() {
            for child in window.childWindows ?? [] {
                child.close()
            }
            window.close()
            workspace.close()
        }
    }

    func makeHarness(in directory: URL, fileName: String = "Notes.md", content: String) throws -> Harness {
        try content.write(to: directory.appending(path: fileName), atomically: true, encoding: .utf8)
        let workspace = WorkspaceDocument()
        try workspace.read(from: directory, ofType: "")
        workspace.makeWindowControllers()
        let controller = try #require(workspace.windowControllers.first as? DreamderWindowController)
        let window = try #require(controller.window)
        window.isReleasedWhenClosed = false
        window.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: false)
        let manager = try #require(workspace.editorManager)
        let file = try #require(workspace.workspaceFileManager?.getFile(
            directory.appending(path: fileName).path(percentEncoded: false),
            createIfNotFound: true
        ))
        manager.openTab(item: file)
        let editorInstance = try #require(manager.activeEditor.selectedTab)
        let codeFile = try #require(editorInstance.file.fileDocument)
        return Harness(
            workspace: workspace,
            controller: controller,
            window: window,
            codeFile: codeFile,
            editorInstance: editorInstance
        )
    }

    @Test
    func theTargetTakesItsSelectionsFromTheFocusedTextViewShowingTheDocument() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory, content: "visit docs now\n")
            defer { harness.close() }
            let textView = try harness.focusedTextView()
            textView.selectionManager.setSelectedRange(NSRange(location: 6, length: 4))

            let target = try #require(harness.controller.markdownEditorTarget())

            #expect(target.textView === textView)
            #expect(target.text == "visit docs now\n")
            #expect(target.selections == [NSRange(location: 6, length: 4)])
        }
    }

    @Test
    func aFocusedViewWithoutSelectionsFallsBackToTheEditorCursors() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory, content: "visit docs now\n")
            defer { harness.close() }
            let textView = try harness.focusedTextView()
            textView.selectionManager.setSelectedRanges([])
            harness.select([NSRange(location: 3, length: 2)])

            let target = try #require(harness.controller.markdownEditorTarget())

            #expect(target.textView === textView)
            #expect(target.selections == [NSRange(location: 3, length: 2)])
        }
    }

    @Test
    func theCaretOffsetIsTheFirstEditorCursorWithoutAFocusedView() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory, content: "visit docs now\n")
            defer { harness.close() }
            harness.select([NSRange(location: 4, length: 0), NSRange(location: 8, length: 2)])

            let target = try #require(harness.controller.markdownEditorTarget())

            #expect(target.textView == nil)
            #expect(target.caretOffset == 4)
            #expect(target.selections == [NSRange(location: 4, length: 0), NSRange(location: 8, length: 2)])
        }
    }

    @Test
    func theCaretOffsetIsTheFirstSelectionOfTheFocusedView() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory, content: "visit docs now\n")
            defer { harness.close() }
            let textView = try harness.focusedTextView()
            textView.selectionManager.setSelectedRange(NSRange(location: 6, length: 4))

            let target = try #require(harness.controller.markdownEditorTarget())

            #expect(target.caretOffset == 6)
        }
    }

    @Test
    func noCursorPositionsResolveToTheStartOfTheText() {
        #expect(MarkdownEditorTarget.ranges(of: [], in: "abc") == [NSRange(location: 0, length: 0)])
    }

    @Test
    func theTargetIgnoresAFocusedViewThatShowsAnotherDocument() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory, content: "text\n")
            defer { harness.close() }
            let other = TextView(string: "other")
            harness.window.contentView?.addSubview(other)
            try #require(harness.window.makeFirstResponder(other))
            harness.select([NSRange(location: 2, length: 1)])

            let target = try #require(harness.controller.markdownEditorTarget())

            #expect(target.textView == nil)
            #expect(target.selections == [NSRange(location: 2, length: 1)])
        }
    }

    @Test
    func theTargetNeedsAMarkdownDocument() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory, fileName: "Code.swift", content: "let a = 1\n")
            defer { harness.close() }

            #expect(harness.controller.markdownEditorTarget() == nil)
            #expect(!harness.controller.performMarkdownCommand(.toggle(.bold)))
        }
    }

    @Test
    func aFormatCommandOutsideATableLeavesTheDocumentUntouched() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory, content: "text\n")
            defer { harness.close() }
            harness.select([NSRange(location: 0, length: 0)])

            harness.controller.markdownFormatTable(nil)

            #expect(harness.text == "text\n")
            #expect(!harness.codeFile.isDocumentEdited)
        }
    }

    @Test
    func commandsEditTheFocusedTextViewAndMoveItsSelection() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory, content: "hello world\n")
            defer { harness.close() }
            let textView = try harness.focusedTextView()
            textView.selectionManager.setSelectedRange(NSRange(location: 0, length: 5))

            let performed = harness.controller.performMarkdownCommand(.toggle(.bold))

            #expect(performed)
            #expect(textView.string == "**hello** world\n")
            #expect(harness.text == "**hello** world\n")
            #expect(textView.selectionManager.textSelections.map(\.range) == [NSRange(location: 2, length: 5)])
        }
    }

    @Test
    func commandsWithoutAFocusedViewEditTheStorageAndMarkTheDocumentEdited() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory, content: "hello world\n")
            defer { harness.close() }
            harness.select([NSRange(location: 0, length: 5)])
            #expect(!harness.codeFile.isDocumentEdited)

            let performed = harness.controller.performMarkdownCommand(.toggle(.bold))

            #expect(performed)
            #expect(harness.text == "**hello** world\n")
            #expect(harness.codeFile.isDocumentEdited)
            #expect(harness.cursorRanges == [NSRange(location: 2, length: 5)])
            harness.codeFile.updateChangeCount(.changeCleared)
        }
    }

    @Test
    func aResultWithoutEditsOnlyMovesTheCursors() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory, content: "hello world\n")
            defer { harness.close() }
            let target = try #require(harness.controller.markdownEditorTarget())
            let units = Array(target.text.utf16)

            let unchanged = MarkdownActionResult(
                original: units,
                updated: units,
                selections: [NSRange(location: 4, length: 0)]
            )
            target.apply(unchanged)

            #expect(harness.text == "hello world\n")
            #expect(!harness.codeFile.isDocumentEdited)
            #expect(harness.cursorRanges == [NSRange(location: 4, length: 0)])
        }
    }

    @Test
    func createLinkTakesAnExistingRelativePathFromTheClipboard() throws {
        try withTempDir { directory in
            try "other\n".write(to: directory.appending(path: "Other.md"), atomically: true, encoding: .utf8)
            let harness = try makeHarness(in: directory, content: "visit docs now\n")
            defer { harness.close() }
            harness.controller.markdownClipboard = { "Other.md" }
            harness.select([NSRange(location: 6, length: 4)])

            harness.controller.markdownCreateLink(nil)

            #expect(harness.text == "visit [docs](Other.md) now\n")
        }
    }

    @Test
    func createLinkIgnoresARelativePathThatDoesNotExist() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory, content: "visit docs now\n")
            defer { harness.close() }
            harness.controller.markdownClipboard = { "Missing.md" }
            harness.select([NSRange(location: 6, length: 4)])

            harness.controller.markdownCreateLink(nil)

            #expect(harness.text == "visit [docs]() now\n")
        }
    }

    @Test
    func createLinkReadsTheInjectedPasteboardByDefault() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory, content: "visit docs now\n")
            defer { harness.close() }
            let pasteboard = InMemoryPasteboard()
            pasteboard.replaceContents(withText: "https://example.com/docs")
            harness.controller.markdownPasteboard = pasteboard
            harness.select([NSRange(location: 6, length: 4)])

            harness.controller.markdownCreateLink(nil)

            #expect(harness.text == "visit [docs](https://example.com/docs) now\n")
        }
    }

    @Test
    func tableOfContentsUsesTheDocumentsIndentOption() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory, content: "\n# Intro\n\n## Deep\n")
            defer { harness.close() }
            harness.select([NSRange(location: 0, length: 0)])

            harness.controller.markdownGenerateTableOfContents(nil)

            #expect(harness.text.hasPrefix("<!-- TOC -->\n"))
            #expect(harness.text.contains("* [Intro](#intro)"))
            #expect(harness.text.contains("[Deep](#deep)"))
        }
    }
}
