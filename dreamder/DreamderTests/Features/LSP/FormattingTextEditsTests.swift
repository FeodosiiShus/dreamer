import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

struct FormattingDiffCase: CustomTestStringConvertible, Sendable {
    let name: String
    let old: String
    let new: String
    let range: NSRange
    let replacement: String

    var testDescription: String { name }
}

@Suite("FormattingTextEdits")
struct FormattingTextEditsTests {
    static let diffCases: [FormattingDiffCase] = [
        FormattingDiffCase(
            name: "middle deletion", old: "let  x = 1", new: "let x = 1",
            range: NSRange(location: 4, length: 1), replacement: ""
        ),
        FormattingDiffCase(
            name: "insertion", old: "ab", new: "aXb",
            range: NSRange(location: 1, length: 0), replacement: "X"
        ),
        FormattingDiffCase(
            name: "deletion", old: "aXb", new: "ab",
            range: NSRange(location: 1, length: 1), replacement: ""
        ),
        FormattingDiffCase(
            name: "append", old: "ab", new: "ab\n",
            range: NSRange(location: 2, length: 0), replacement: "\n"
        ),
        FormattingDiffCase(
            name: "replace everything", old: "abc", new: "xyz",
            range: NSRange(location: 0, length: 3), replacement: "xyz"
        ),
        FormattingDiffCase(
            name: "from empty", old: "", new: "abc",
            range: NSRange(location: 0, length: 0), replacement: "abc"
        ),
        FormattingDiffCase(
            name: "to empty", old: "abc", new: "",
            range: NSRange(location: 0, length: 3), replacement: ""
        ),
        FormattingDiffCase(
            name: "emoji sharing the high surrogate", old: "a\u{1F600}b", new: "a\u{1F601}b",
            range: NSRange(location: 1, length: 2), replacement: "\u{1F601}"
        ),
        FormattingDiffCase(
            name: "emoji sharing the low surrogate", old: "\u{1F600}", new: "\u{1FA00}",
            range: NSRange(location: 0, length: 2), replacement: "\u{1FA00}"
        ),
        FormattingDiffCase(
            name: "carriage return before a changed line feed", old: "a\r\nb", new: "a\rb",
            range: NSRange(location: 1, length: 2), replacement: "\r"
        ),
        FormattingDiffCase(
            name: "line feed after a changed carriage return", old: "a\r\nb", new: "a\nb",
            range: NSRange(location: 1, length: 2), replacement: "\n"
        )
    ]

    static let onTypeOptions = DocumentOnTypeFormattingOptions(
        firstTriggerCharacter: "}",
        moreTriggerCharacter: [";", "\n"]
    )

    private func position(_ offset: Int, in text: String) -> Position {
        FormattingTextPositions.position(atOffset: offset, in: Array(text.utf16))
    }

    @Test
    func positionsCountLineFeedsCarriageReturnsAndCRLFAsOneBreak() {
        #expect(position(0, in: "ab\ncd") == Position(line: 0, character: 0))
        #expect(position(2, in: "ab\ncd") == Position(line: 0, character: 2))
        #expect(position(3, in: "ab\ncd") == Position(line: 1, character: 0))
        #expect(position(5, in: "ab\ncd") == Position(line: 1, character: 2))
        #expect(position(3, in: "ab\rcd") == Position(line: 1, character: 0))
        #expect(position(4, in: "ab\r\ncd") == Position(line: 1, character: 0))
        #expect(position(6, in: "ab\r\ncd") == Position(line: 1, character: 2))
        #expect(position(3, in: "ab\r\ncd") == Position(line: 1, character: 0))
    }

    @Test
    func positionsClampTheOffsetToTheText() {
        #expect(position(-4, in: "ab") == Position(line: 0, character: 0))
        #expect(position(99, in: "ab\nc") == Position(line: 1, character: 1))
        #expect(position(0, in: "") == Position(line: 0, character: 0))
    }

    @Test
    func positionsCountUTF16Units() {
        #expect(position(2, in: "\u{1F600}x") == Position(line: 0, character: 2))
    }

    @Test
    func wholeDocumentRangeEndsAtTheLastCharacter() {
        #expect(FormattingTextPositions.wholeDocumentRange(of: "a\nbc") == LSPRange(
            start: Position(line: 0, character: 0),
            end: Position(line: 1, character: 2)
        ))
        #expect(FormattingTextPositions.wholeDocumentRange(of: "a\n") == LSPRange(
            start: Position(line: 0, character: 0),
            end: Position(line: 1, character: 0)
        ))
        #expect(FormattingTextPositions.wholeDocumentRange(of: "") == LSPRange(
            start: Position(line: 0, character: 0),
            end: Position(line: 0, character: 0)
        ))
    }

    @Test
    func rangesConvertSelectionsToLSPRanges() {
        let units = Array("one\ntwo\nthree".utf16)

        let range = FormattingTextPositions.range(of: NSRange(location: 2, length: 7), in: units)

        #expect(range == LSPRange(start: Position(line: 0, character: 2), end: Position(line: 2, character: 1)))
    }

    @Test(arguments: diffCases)
    func minimalEditsReplaceOnlyTheDifferingRangeAndReproduceTheNewText(_ item: FormattingDiffCase) throws {
        let resolved = try #require(MinimalTextEdit.between(item.old, item.new))

        #expect(resolved.range == item.range)
        #expect(resolved.edit.newText == item.replacement)
        #expect(try LSPTextEditApplier.apply([resolved.edit], to: item.old) == item.new)
    }

    @Test
    func identicalTextsProduceNoEdit() {
        #expect(MinimalTextEdit.between("same\n", "same\n") == nil)
    }

    @Test
    func editsCarryLSPPositionsAcrossLines() throws {
        let resolved = try #require(MinimalTextEdit.between("a\nb\nc", "a\nB\nc"))

        #expect(resolved.edit.range == LSPRange(
            start: Position(line: 1, character: 0),
            end: Position(line: 1, character: 1)
        ))
        #expect(resolved.edit.newText == "B")
    }

    @Test(arguments: [
        ("}", "}" as String?),
        (";", ";"),
        ("\n", "\n"),
        ("a", nil),
        ("}}", nil),
        ("", nil),
        ("\u{1F600}\u{1F600}", nil)
    ])
    func onTypeTriggersAreSingleCharactersListedByTheServer(_ inserted: String, _ expected: String?) {
        #expect(OnTypeFormattingTrigger.character(inserted: inserted, options: Self.onTypeOptions) == expected)
    }

    @Test
    func onTypeTriggersWithoutMoreCharactersOnlyMatchTheFirst() {
        let options = DocumentOnTypeFormattingOptions(firstTriggerCharacter: ")")

        #expect(OnTypeFormattingTrigger.character(inserted: ")", options: options) == ")")
        #expect(OnTypeFormattingTrigger.character(inserted: ";", options: options) == nil)
    }

    @Test
    func caretFollowsTheInsertedText() {
        let plain = OnTypeFormattingTrigger.caretOffset(afterInserting: "}", replacing: NSRange(location: 4, length: 0))
        let emoji = OnTypeFormattingTrigger.caretOffset(
            afterInserting: "\u{1F600}",
            replacing: NSRange(location: 4, length: 2)
        )

        #expect(plain == 5)
        #expect(emoji == 6)
    }

    @Test
    func onlyASingleCaretRightAfterTheInsertionCountsAsTyping() {
        #expect(OnTypeFormattingTrigger.isTyped(caretOffset: 5, selections: [NSRange(location: 5, length: 0)]))
        #expect(!OnTypeFormattingTrigger.isTyped(caretOffset: 5, selections: [NSRange(location: 4, length: 0)]))
        #expect(!OnTypeFormattingTrigger.isTyped(caretOffset: 5, selections: [NSRange(location: 5, length: 1)]))
        #expect(!OnTypeFormattingTrigger.isTyped(
            caretOffset: 5,
            selections: [NSRange(location: 5, length: 0), NSRange(location: 9, length: 0)]
        ))
        #expect(!OnTypeFormattingTrigger.isTyped(caretOffset: 5, selections: []))
    }
}
