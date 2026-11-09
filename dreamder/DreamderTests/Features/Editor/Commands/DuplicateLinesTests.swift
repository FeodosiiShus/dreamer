import Foundation
import Testing
@testable import Dreamder

struct DuplicateLinesTests {
    private static let fixtureDirectory = "platform/platform-tests/testData/editor/multiCaret"

    private func duplicated(_ markup: String) throws -> String {
        let source = EditorMarkup(markup)
        let result = try #require(DuplicateLines.perform(in: NSString(string: source.text), selections: source.selections))
        let storage = NSMutableString(string: source.text)
        for edit in result.edits.sorted(by: { $0.range.location > $1.range.location }) {
            storage.replaceCharacters(in: edit.range, with: edit.replacement)
        }
        return EditorMarkup(text: storage as String, selections: result.selections).rendered
    }

    @Test
    func editorDuplicateFixtureMatchesIntelliJ() throws {
        let before = try IntelliJTestData.text("\(Self.fixtureDirectory)/EditorDuplicate-before.txt")
        let after = try IntelliJTestData.text("\(Self.fixtureDirectory)/EditorDuplicate-after.txt")
        #expect(try duplicated(before) == EditorMarkup.normalized(after))
    }

    @Test
    func caretOnFirstLineOfSingleLineDocumentDuplicatesBelow() throws {
        #expect(try duplicated("long long t<caret>ext") == EditorMarkup.normalized("long long text\nlong long t<caret>ext"))
    }

    @Test
    func caretOnTerminatedLineKeepsItsColumnOnTheCopy() throws {
        #expect(try duplicated("ab<caret>c\nxyz\n") == EditorMarkup.normalized("abc\nab<caret>c\nxyz\n"))
    }

    @Test
    func caretOnTrailingEmptyLineAddsAnotherEmptyLine() throws {
        #expect(try duplicated("a\n<caret>") == EditorMarkup.normalized("a\n\n<caret>"))
    }

    @Test
    func severalCaretsOnOneLineProduceOneCopyEach() throws {
        #expect(
            try duplicated("a<caret>b<caret>c\nz") == EditorMarkup.normalized("abc\na<caret>bc\nab<caret>c\nz")
        )
    }

    @Test
    func selectionEndingAtDocumentEndSharesTheInsertionPointWithTheLineCopy() throws {
        #expect(
            try duplicated("<caret>a<selection>bc</selection>")
                == EditorMarkup.normalized("abc<selection>bc<caret></selection>\n<caret>abc")
        )
    }

    @Test
    func selectionSpanningLinesIsDuplicatedVerbatimAndSelected() throws {
        #expect(
            try duplicated("x<selection>1\n2</selection>y\nz") == EditorMarkup.normalized("x1\n2<selection>1\n2<caret></selection>y\nz")
        )
    }

    @Test
    func noSelectionsMeansNothingToDo() {
        #expect(DuplicateLines.perform(in: "abc", selections: []) == nil)
    }
}

@MainActor
@Suite(.uiGate)
struct DuplicateLinesHostedTests {
    @Test
    func duplicatesTheLineBelowForASingleCaret() async throws {
        try await withTempDir { directory in
            let harness = try await EditorCommandHarness.open(in: directory, markup: "ab<caret>c\nxyz")
            defer { harness.close() }
            harness.actions.duplicateLineOrSelection()
            #expect(harness.rendered == EditorMarkup.normalized("abc\nab<caret>c\nxyz"))
        }
    }

    @Test
    func duplicatesTheIntelliJMultiCaretFixtureAndUndoesInOneStep() async throws {
        let before = try IntelliJTestData.text("platform/platform-tests/testData/editor/multiCaret/EditorDuplicate-before.txt")
        let after = try IntelliJTestData.text("platform/platform-tests/testData/editor/multiCaret/EditorDuplicate-after.txt")
        try await withTempDir { directory in
            let harness = try await EditorCommandHarness.open(in: directory, markup: before)
            defer { harness.close() }
            let original = harness.text
            harness.actions.duplicateLineOrSelection()
            #expect(harness.rendered == EditorMarkup.normalized(after))
            harness.textView.undoManager?.undo()
            #expect(harness.text == original)
        }
    }
}
