import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

@Suite("LSP completion edit planner")
struct LSPCompletionEditPlannerTests {
    private let document = "let x = fo\nlet y = 1\n"

    private func position(_ line: Int, _ character: Int) -> Position {
        Position(line: line, character: character)
    }

    private func range(_ line: Int, _ start: Int, _ end: Int) -> LSPRange {
        LSPRange(start: position(line, start), end: position(line, end))
    }

    private func offsets() -> (Position) -> Int? {
        var starts = [0]
        var cursor = 0
        for unit in document.utf16 {
            cursor += 1
            if unit == 10 { starts.append(cursor) }
        }
        let lineStarts = starts
        let length = document.utf16.count
        return { position in
            guard position.line >= 0, position.line < lineStarts.count else { return nil }
            let offset = lineStarts[position.line] + position.character
            return offset <= length ? offset : nil
        }
    }

    private func makePlan(
        _ item: CompletionItem,
        current: Position? = nil,
        allowsSnippet: Bool = true
    ) -> LSPCompletionEditPlan? {
        LSPCompletionEditPlanner.plan(
            item: item,
            context: LSPCompletionRequestContext(position: position(0, 10)),
            current: current ?? position(0, 10),
            fallbackRange: NSRange(location: 8, length: 2),
            variables: SnippetVariableContext(),
            allowsSnippet: allowsSnippet,
            offsetOf: offsets()
        )
    }

    private func edit(_ location: Int, _ length: Int, _ text: String) -> LSPCompletionEdit {
        LSPCompletionEdit(range: NSRange(location: location, length: length), text: text)
    }

    @Test func itemsWithoutATextEditReplaceTheTypedPrefix() throws {
        let plan = try #require(makePlan(CompletionItem(label: "foo")))
        #expect(plan.edits == [edit(8, 2, "foo")])
        #expect(plan.mainStart == 8)
        #expect(plan.mainLength == 3)
        #expect(plan.caret == 11)
        #expect(plan.template == nil)
    }

    @Test func insertTextWinsOverTheLabel() throws {
        let plan = try #require(makePlan(CompletionItem(label: "foo", insertText: "foo()")))
        #expect(plan.edits == [edit(8, 2, "foo()")])
        #expect(plan.caret == 13)
    }

    @Test func aTextEditRangeIsHonoured() throws {
        let item = CompletionItem(
            label: "foo",
            textEdit: .optionA(TextEdit(range: range(0, 4, 10), newText: "foo"))
        )
        let plan = try #require(makePlan(item))
        #expect(plan.edits == [edit(4, 6, "foo")])
        #expect(plan.mainStart == 4)
        #expect(plan.caret == 7)
    }

    @Test func anInsertReplaceEditUsesItsInsertRange() throws {
        let item = CompletionItem(
            label: "foo",
            textEdit: .optionB(InsertReplaceEdit(newText: "foo", insert: range(0, 8, 10), replace: range(0, 8, 10)))
        )
        let plan = try #require(makePlan(item))
        #expect(plan.edits == [edit(8, 2, "foo")])
    }

    @Test func charactersTypedSinceTheRequestExtendTheRangeEnd() throws {
        let item = CompletionItem(
            label: "foo",
            textEdit: .optionA(TextEdit(range: range(0, 8, 10), newText: "foo"))
        )
        let plan = try #require(makePlan(item, current: position(0, 12)))
        #expect(plan.edits == [edit(8, 4, "foo")])
    }

    @Test func aZeroWidthRangeAtTheRequestPositionCoversTheTypedPrefix() throws {
        let context = LSPCompletionRequestContext(position: position(0, 8))
        let item = CompletionItem(
            label: "foo",
            textEdit: .optionA(TextEdit(range: range(0, 8, 8), newText: "foo"))
        )
        let result = LSPCompletionEditPlanner.plan(
            item: item,
            context: context,
            current: position(0, 10),
            fallbackRange: NSRange(location: 8, length: 2),
            variables: SnippetVariableContext(),
            allowsSnippet: true,
            offsetOf: offsets()
        )
        #expect(result?.edits == [edit(8, 2, "foo")])
    }

    @Test func positionsOnOtherLinesAreNotShifted() {
        let context = LSPCompletionRequestContext(position: position(0, 8))
        #expect(
            LSPCompletionEditPlanner.adjusted(position(1, 5), isEnd: true, context: context, current: position(0, 10))
                == position(1, 5)
        )
        #expect(
            LSPCompletionEditPlanner.adjusted(position(0, 5), isEnd: true, context: context, current: position(1, 10))
                == position(0, 5)
        )
        #expect(
            LSPCompletionEditPlanner.adjusted(position(0, 5), isEnd: true, context: context, current: position(0, 10))
                == position(0, 5)
        )
        #expect(
            LSPCompletionEditPlanner.adjusted(position(0, 8), isEnd: false, context: context, current: position(0, 10))
                == position(0, 8)
        )
        #expect(
            LSPCompletionEditPlanner.adjusted(position(0, 8), isEnd: true, context: context, current: position(0, 10))
                == position(0, 10)
        )
        #expect(
            LSPCompletionEditPlanner.adjusted(position(0, 9), isEnd: false, context: context, current: position(0, 10))
                == position(0, 11)
        )
    }

    @Test func additionalEditsAreAppliedTogetherWithTheMainEdit() throws {
        let item = CompletionItem(
            label: "foo",
            textEdit: .optionA(TextEdit(range: range(0, 8, 10), newText: "foo")),
            additionalTextEdits: [TextEdit(range: range(0, 0, 0), newText: "import Foo\n")]
        )
        let plan = try #require(makePlan(item))
        #expect(plan.edits == [edit(8, 2, "foo"), edit(0, 0, "import Foo\n")])
        #expect(plan.mainStart == 19)
        #expect(plan.caret == 22)
    }

    @Test func additionalEditsAfterTheMainEditDoNotMoveIt() throws {
        let item = CompletionItem(
            label: "foo",
            additionalTextEdits: [TextEdit(range: range(1, 0, 3), newText: "var")]
        )
        let plan = try #require(makePlan(item))
        #expect(plan.edits == [edit(11, 3, "var"), edit(8, 2, "foo")])
        #expect(plan.mainStart == 8)
    }

    @Test func additionalEditsOverlappingTheMainEditAreDropped() throws {
        let item = CompletionItem(
            label: "foo",
            additionalTextEdits: [
                TextEdit(range: range(0, 9, 10), newText: "x"),
                TextEdit(range: range(0, 9, 9), newText: "y"),
                TextEdit(range: range(0, 0, 0), newText: "ok")
            ]
        )
        let plan = try #require(makePlan(item))
        #expect(plan.edits == [edit(8, 2, "foo"), edit(0, 0, "ok")])
    }

    @Test func additionalEditsWithInvalidRangesAreDropped() throws {
        let item = CompletionItem(
            label: "foo",
            additionalTextEdits: [TextEdit(range: range(9, 0, 0), newText: "x")]
        )
        let plan = try #require(makePlan(item))
        #expect(plan.edits == [edit(8, 2, "foo")])
    }

    @Test func anInvalidMainRangeYieldsNoPlan() {
        let outside = CompletionItem(
            label: "foo",
            textEdit: .optionA(TextEdit(range: range(9, 0, 0), newText: "foo"))
        )
        #expect(makePlan(outside) == nil)
        let reversed = CompletionItem(
            label: "foo",
            textEdit: .optionA(TextEdit(range: range(0, 5, 2), newText: "foo"))
        )
        #expect(makePlan(reversed) == nil)
    }

    @Test func insertionsAtTheSameOffsetKeepTheirOrder() throws {
        let item = CompletionItem(
            label: "foo",
            additionalTextEdits: [
                TextEdit(range: range(0, 0, 0), newText: "1"),
                TextEdit(range: range(0, 0, 0), newText: "2")
            ]
        )
        let plan = try #require(makePlan(item))
        #expect(plan.edits == [edit(8, 2, "foo"), edit(0, 0, "2"), edit(0, 0, "1")])
        #expect(plan.mainStart == 10)
    }

    @Test func aReplacementStartingAtAnEmptyMainRangeIsAppliedFirst() throws {
        let context = LSPCompletionRequestContext(position: position(0, 10))
        let item = CompletionItem(
            label: "foo",
            textEdit: .optionA(TextEdit(range: range(0, 10, 10), newText: "foo")),
            additionalTextEdits: [
                TextEdit(range: LSPRange(start: position(0, 10), end: position(1, 3)), newText: "x")
            ]
        )
        let result = LSPCompletionEditPlanner.plan(
            item: item,
            context: context,
            current: position(0, 10),
            fallbackRange: NSRange(location: 10, length: 0),
            variables: SnippetVariableContext(),
            allowsSnippet: true,
            offsetOf: offsets()
        )
        #expect(result?.edits == [edit(10, 4, "x"), edit(10, 0, "foo")])
    }

    @Test func snippetsBecomeATemplateAndTheFlattenedText() throws {
        let item = CompletionItem(
            label: "foo",
            insertText: "foo(${1:a}, ${2:b})$0",
            insertTextFormat: .snippet
        )
        let plan = try #require(makePlan(item))
        #expect(plan.edits == [edit(8, 2, "foo(a, b)")])
        #expect(plan.mainLength == 9)
        #expect(plan.template?.tabStops.map(\.index) == [1, 2])
        #expect(plan.template?.finalCaret == 9)
    }

    @Test func snippetsAreFlattenedWhenTheyMayNotStartASession() throws {
        let item = CompletionItem(label: "foo", insertText: "foo(${1:a})", insertTextFormat: .snippet)
        let plan = try #require(makePlan(item, allowsSnippet: false))
        #expect(plan.edits == [edit(8, 2, "foo(a)")])
        #expect(plan.template == nil)
    }

    @Test func lineSeparatorsAreNormalized() throws {
        let item = CompletionItem(
            label: "foo",
            insertText: "a\r\nb\rc",
            additionalTextEdits: [TextEdit(range: range(0, 0, 0), newText: "x\r\ny")]
        )
        let plan = try #require(makePlan(item))
        #expect(plan.edits == [edit(8, 2, "a\nb\nc"), edit(0, 0, "x\ny")])
    }
}
