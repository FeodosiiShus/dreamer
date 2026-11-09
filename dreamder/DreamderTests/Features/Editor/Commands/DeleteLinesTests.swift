import Foundation
import Testing
@testable import Dreamder

struct DeleteLinesTests {
    private static let fixtureDirectory = "platform/platform-tests/testData/editor/multiCaret"

    private func deleted(_ markup: String) throws -> String {
        let source = EditorMarkup(markup)
        let result = try #require(DeleteLines.perform(in: NSString(string: source.text), selections: source.selections))
        let storage = NSMutableString(string: source.text)
        for edit in result.edits.sorted(by: { $0.range.location > $1.range.location }) {
            storage.replaceCharacters(in: edit.range, with: edit.replacement)
        }
        return EditorMarkup(text: storage as String, selections: result.selections).rendered
    }

    @Test
    func editorDeleteLineFixtureMatchesIntelliJ() throws {
        let before = try IntelliJTestData.text("\(Self.fixtureDirectory)/EditorDeleteLine-before.txt")
        let after = try IntelliJTestData.text("\(Self.fixtureDirectory)/EditorDeleteLine-after.txt")
        #expect(try deleted(before) == EditorMarkup.normalized(after))
    }

    @Test
    func selectionEndingAtLineStartKeepsTheNextLine() throws {
        #expect(
            try deleted("line 1\n<selection>line 2\n</selection>line 3") == EditorMarkup.normalized("line 1\n<caret>line 3")
        )
    }

    @Test
    func deletingTheLastLineTwiceLeavesTheFirstLine() throws {
        let once = try deleted("1\n2<caret>\n3")
        #expect(once == EditorMarkup.normalized("1\n3<caret>"))
        #expect(try deleted(once) == EditorMarkup.normalized("1<caret>"))
    }

    @Test
    func deletingTheOnlyTerminatedLineEmptiesTheDocument() throws {
        #expect(try deleted("<caret>1\n") == EditorMarkup.normalized("<caret>"))
    }

    @Test
    func selectionAcrossLinesDeletesEveryTouchedLine() throws {
        #expect(
            try deleted("xxxx\nbla <selection>bla\nbla</selection> bla\nyyy") == EditorMarkup.normalized("xxxx\nyyy<caret>")
        )
    }

    @Test
    func caretColumnIsClampedToTheLineThatMovesIn() throws {
        #expect(try deleted("abcdef<caret>\nxy\nzzz") == EditorMarkup.normalized("xy<caret>\nzzz"))
    }

    @Test
    func lastLineDeletionMovesTheCaretToTheLineAbove() throws {
        #expect(try deleted("a\nb<caret>") == EditorMarkup.normalized("a<caret>"))
    }

    @Test
    func windowsLineTerminatorsAreRemovedWithTheirLine() throws {
        #expect(try deleted("a\r\nb<caret>\r\nc") == EditorMarkup.normalized("a\r\nc<caret>"))
        #expect(try deleted("a\r\nb<caret>") == EditorMarkup.normalized("a<caret>"))
    }

    @Test
    func emptyDocumentHasNothingToDelete() {
        #expect(DeleteLines.perform(in: "", selections: [NSRange(location: 0, length: 0)]) == nil)
    }

    @Test
    func noSelectionsMeansNothingToDo() {
        #expect(DeleteLines.perform(in: "abc", selections: []) == nil)
    }
}

@MainActor
@Suite(.uiGate)
struct DeleteLinesHostedTests {
    @Test
    func deletesTheCaretLine() async throws {
        try await withTempDir { directory in
            let harness = try await EditorCommandHarness.open(in: directory, markup: "one\ntw<caret>o\nthree")
            defer { harness.close() }
            harness.actions.deleteLine()
            #expect(harness.rendered == EditorMarkup.normalized("one\nth<caret>ree"))
        }
    }

    @Test
    func deletesTheIntelliJMultiCaretFixtureAndUndoesInOneStep() async throws {
        let before = try IntelliJTestData.text("platform/platform-tests/testData/editor/multiCaret/EditorDeleteLine-before.txt")
        let after = try IntelliJTestData.text("platform/platform-tests/testData/editor/multiCaret/EditorDeleteLine-after.txt")
        try await withTempDir { directory in
            let harness = try await EditorCommandHarness.open(in: directory, markup: before)
            defer { harness.close() }
            let original = harness.text
            harness.actions.deleteLine()
            #expect(harness.rendered == EditorMarkup.normalized(after))
            harness.textView.undoManager?.undo()
            #expect(harness.text == original)
        }
    }
}
