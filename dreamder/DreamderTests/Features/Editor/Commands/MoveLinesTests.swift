import Foundation
import Testing
@testable import Dreamder

struct MoveLinesTests {
    private static let fixtureDirectory = "java/java-tests/testData/codeInsight/moveStatementAction"

    private func moved(_ markup: String, up: Bool) -> String? {
        let source = EditorMarkup(markup)
        guard let result = MoveLines.perform(in: NSString(string: source.text), selections: source.selections, up: up) else {
            return nil
        }
        let storage = NSMutableString(string: source.text)
        for edit in result.edits.sorted(by: { $0.range.location > $1.range.location }) {
            storage.replaceCharacters(in: edit.range, with: edit.replacement)
        }
        return EditorMarkup(text: storage as String, selections: result.selections).rendered
    }

    private func normalized(_ markup: String) -> String {
        EditorMarkup.normalized(markup)
    }

    @Test
    func caretLineMovesDownPastItsNeighbour() {
        #expect(moved("<caret>alpha\nbravo\ncharlie\n", up: false) == normalized("bravo\n<caret>alpha\ncharlie\n"))
    }

    @Test
    func caretLineMovesUpPastItsNeighbour() {
        #expect(moved("alpha\nbravo\nc<caret>harlie\n", up: true) == normalized("alpha\nc<caret>harlie\nbravo\n"))
    }

    @Test
    func caretOffsetOfThirteenSwapsLineTwoWithLineOne() {
        let text = NSString(string: "alpha\nbravo\ncharlie\n")
        let result = MoveLines.perform(in: text, selections: [NSRange(location: 13, length: 0)], up: true)
        #expect(result?.selections == [NSRange(location: 7, length: 0)])
        #expect(result?.edits == [EditorTextEdit(range: NSRange(location: 6, length: 13), replacement: "charlie\nbravo")])
    }

    @Test
    func blocksAtTheDocumentEdgesStayPut() {
        #expect(moved("<caret>a\nb\n", up: true) == nil)
        #expect(moved("a\n<caret>b\n", up: false) == nil)
    }

    @Test
    func trailingEmptyLineCannotBeMoved() {
        #expect(moved("a\nb\n<caret>", up: true) == nil)
        #expect(moved("<caret>", up: false) == nil)
    }

    @Test
    func lastUnterminatedLineMovesUp() {
        #expect(moved("a\nb\nc<caret>", up: true) == normalized("a\nc<caret>\nb"))
    }

    @Test
    func lineMovesDownOntoTheLastUnterminatedLine() {
        #expect(moved("a<caret>\nb", up: false) == normalized("b\na<caret>"))
    }

    @Test
    func everyCaretMovesItsOwnLineDown() {
        #expect(moved("a<caret>\nb\nc<caret>\nd", up: false) == normalized("b\na<caret>\nd\nc<caret>"))
    }

    @Test
    func everyCaretMovesItsOwnLineUp() {
        #expect(moved("a\nb<caret>\nc\nd<caret>", up: true) == normalized("b<caret>\na\nd<caret>\nc"))
    }

    @Test
    func adjacentCaretLinesMoveAsOneBlock() {
        #expect(moved("a\nb<caret>\nc<caret>\nd", up: true) == normalized("b<caret>\nc<caret>\na\nd"))
    }

    @Test
    func blockAtTheEdgeStaysWhileTheOtherBlockMoves() {
        #expect(moved("a<caret>\nb\nc<caret>\nd", up: true) == normalized("a<caret>\nc<caret>\nb\nd"))
    }

    @Test
    func selectionEndingAtLineStartMovesDownAndStaysSelected() {
        #expect(
            moved("x\n<selection>a\nb\n</selection>y\nz", up: false) == normalized("x\ny\n<selection>a\nb\n</selection>z")
        )
    }

    @Test
    func selectionEndingAtLineStartMovesUpAndStaysSelected() {
        #expect(
            moved("x\ny\n<selection>a\nb\n</selection>z", up: true) == normalized("x\n<selection>a\nb\n</selection>y\nz")
        )
    }

    @Test
    func selectionEndingAtTheTrailingEmptyLineMovesUp() {
        #expect(moved("a\n<selection>b\n</selection>", up: true) == normalized("<selection>b\n</selection>a\n"))
    }

    @Test
    func caretOnTheTrailingEmptyLineStaysWhileTheLineAboveMoves() {
        #expect(moved("a\n<caret>b\n<caret>", up: true) == normalized("<caret>b\na\n<caret>"))
        #expect(moved("a\n<caret>b\n<caret>", up: false) == nil)
    }

    @Test
    func lineTerminatorsStayAtTheirPosition() {
        #expect(moved("a<caret>\r\nb\nc", up: false) == normalized("b\r\na<caret>\nc"))
    }

    @Test
    func noSelectionsMeansNothingToDo() {
        #expect(MoveLines.perform(in: "a\nb", selections: [], up: false) == nil)
    }

    @Test
    func lineMoverFixturesMatchIntelliJ() throws {
        let commentBefore = try IntelliJTestData.text("\(Self.fixtureDirectory)/commentAtLineStart.java")
        let commentUp = try IntelliJTestData.text("\(Self.fixtureDirectory)/commentAtLineStart_afterUp.java")
        let commentDown = try IntelliJTestData.text("\(Self.fixtureDirectory)/commentAtLineStart_afterDown.java")
        #expect(moved(commentBefore, up: true) == normalized(commentUp))
        #expect(moved(commentBefore, up: false) == normalized(commentDown))

        let selectionBefore = try IntelliJTestData.text("\(Self.fixtureDirectory)/selection.java")
            .replacingOccurrences(of: "<caret><selection>", with: "<selection>")
        let selectionUp = try IntelliJTestData.text("\(Self.fixtureDirectory)/selection_afterUp.java")
            .replacingOccurrences(of: "<caret><selection>", with: "<selection>")
        #expect(moved(selectionBefore, up: true) == normalized(selectionUp))
    }
}

@MainActor
@Suite(.uiGate)
struct MoveLinesHostedTests {
    @Test
    func movesTheCaretLineDownAndUpAgain() async throws {
        try await withTempDir { directory in
            let harness = try await EditorCommandHarness.open(in: directory, markup: "<caret>alpha\nbravo\ncharlie\n")
            defer { harness.close() }
            harness.actions.moveLines(up: false)
            #expect(harness.rendered == EditorMarkup.normalized("bravo\n<caret>alpha\ncharlie\n"))
            harness.actions.moveLines(up: true)
            #expect(harness.rendered == EditorMarkup.normalized("<caret>alpha\nbravo\ncharlie\n"))
        }
    }

    @Test
    func movesEveryCaretLineAndUndoesInOneStep() async throws {
        try await withTempDir { directory in
            let harness = try await EditorCommandHarness.open(in: directory, markup: "a\nb<caret>\nc\nd<caret>")
            defer { harness.close() }
            let original = harness.text
            harness.actions.moveLines(up: true)
            #expect(harness.rendered == EditorMarkup.normalized("b<caret>\na\nd<caret>\nc"))
            harness.textView.undoManager?.undo()
            #expect(harness.text == original)
        }
    }

    @Test
    func movesASelectedBlockAndKeepsItSelected() async throws {
        try await withTempDir { directory in
            let harness = try await EditorCommandHarness.open(in: directory, markup: "x\n<selection>a\nb\n</selection>y\nz")
            defer { harness.close() }
            harness.actions.moveLines(up: false)
            #expect(harness.rendered == EditorMarkup.normalized("x\ny\n<selection>a\nb\n</selection>z"))
        }
    }
}
