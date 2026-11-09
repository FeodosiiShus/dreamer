import Foundation
import Testing
@testable import Dreamder

@Suite
struct MarkdownListEnterCaretSafetyTests {
    private static let settingsVariants: [MarkdownTypingSettings] = [
        MarkdownTypingSettings(),
        MarkdownTypingSettings(smartEnterAndBackspace: false),
        MarkdownTypingSettings(renumberListsOnType: true, listNumberingType: .ones),
        MarkdownTypingSettings(adjustListIndentation: false, tabWidth: 2),
        MarkdownTypingSettings(renumberListsOnType: true, listNumberingType: .previousNumber, tabWidth: 8)
    ]

    private static let fixedDocuments: [String] = [
        "",
        "\r\n",
        "\r",
        "\n\r",
        "\r\n\r\n",
        "- ",
        "- \r\n",
        "a\r\nb",
        "- a\r\n- b\r\n  - c\r\n",
        "1. one\r2. two\r3. 😀 three\r",
        "> - quote 😀\n> > - nested\r\n\r\n```\r\ncode\r\n```\r\n",
        "- e\u{301} cafe\u{301}\r\n- 👨‍👩‍👧 family\n\t- tab\r\n    text",
        "- [ ] task\r\n- [x] done 🎉\r\n\r\n    indented code\r\n",
        "```\r\n- not a list\r\n```\r\n- real\r\n"
    ]

    private static let fragments = [
        "- ", "1. ", "> ", "  ", "\t", "\r\n", "\r", "\n", "x", "😀", "e\u{301}", "```", "- [ ] ", "* ", "a", "2) "
    ]

    private static var randomDocuments: [String] {
        var generator = SeededRandomNumberGenerator(seed: 0xC0DE_0005)
        return (0..<40).map { _ in
            (0..<12).compactMap { _ in fragments.randomElement(using: &generator) }.joined()
        }
    }

    private static var documents: [String] {
        fixedDocuments + randomDocuments
    }

    private static func isValidInsertionPoint(_ units: [UInt16], _ offset: Int) -> Bool {
        let insideCRLF = offset > 0 && offset < units.count && units[offset - 1] == 13 && units[offset] == 10
        let insideSurrogatePair = offset > 0 && offset < units.count
            && (0xD800...0xDBFF).contains(units[offset - 1]) && (0xDC00...0xDFFF).contains(units[offset])
        return !insideCRLF && !insideSurrogatePair
    }

    private func expectWellFormed(_ edit: MarkdownTypingEdit, in text: String, _ label: String) {
        let length = text.utf16.count
        #expect(edit.range.location >= 0, "\(label)")
        #expect(NSMaxRange(edit.range) <= length, "\(label)")
        guard edit.range.location >= 0, NSMaxRange(edit.range) <= length else { return }
        let result = edit.applied(to: text)
        #expect(result.caret >= 0 && result.caret <= result.text.utf16.count, "\(label)")
        if !text.contains("\u{FFFD}") {
            #expect(!result.text.contains("\u{FFFD}"), "\(label)")
        }
    }

    @Test
    func enterBetweenCarriageReturnAndLineFeedProducesNoEdit() {
        #expect(MarkdownListEnter.edit(forEnterIn: "a\r\nb", caret: 2) == nil)
        #expect(MarkdownListEnter.edit(forEnterIn: "- a\r\n- b", caret: 4) == nil)
        #expect(MarkdownListEnter.edit(forEnterIn: "- a\r\n- b", caret: 4, shift: true) == nil)
        #expect(MarkdownListEnter.edit(forEnterIn: "```\r\n```", caret: 4) == nil)
        #expect(MarkdownListEnter.edit(forEnterIn: "\r\n", caret: 1) == nil)
    }

    @Test
    func backspaceBetweenCarriageReturnAndLineFeedProducesNoEdit() {
        #expect(MarkdownListEnter.edit(forBackspaceIn: "a\r\nb", caret: 2) == nil)
        #expect(MarkdownListEnter.edit(forBackspaceIn: "- a\r\n- b", caret: 4) == nil)
        #expect(MarkdownListEnter.edit(forBackspaceIn: "\r\n", caret: 1) == nil)
    }

    @Test
    func caretsNextToCarriageReturnAndLineFeedStillWork() throws {
        let enter = try #require(MarkdownListEnter.edit(forEnterIn: "- a\r\n- b", caret: 3))
        #expect(enter.applied(to: "- a\r\n- b").text == "- a\r\n- \r\n- b")
        let backspace = try #require(MarkdownListEnter.edit(forBackspaceIn: "- a\r\n- b", caret: 7))
        #expect(backspace.applied(to: "- a\r\n- b").text == "- a\r\nb")
    }

    @Test
    func caretInsideASurrogatePairProducesNoEdit() throws {
        let text = "- 😀 item"
        #expect(MarkdownListEnter.edit(forEnterIn: text, caret: 3) == nil)
        #expect(MarkdownListEnter.edit(forEnterIn: text, caret: 3, shift: true) == nil)
        #expect(MarkdownListEnter.edit(forBackspaceIn: text, caret: 3) == nil)

        let afterPair = try #require(MarkdownListEnter.edit(forEnterIn: text, caret: 4))
        let result = afterPair.applied(to: text)
        #expect(result.text == "- 😀\n- item")
        #expect(result.caret == 7)
    }

    @Test
    func caretInsideACombiningSequenceIsAValidInsertionPoint() throws {
        let text = "- e\u{301}x"
        let edit = try #require(MarkdownListEnter.edit(forEnterIn: text, caret: 3))
        #expect(edit.applied(to: text).text == "- e\n- \u{301}x")
    }

    @Test
    func surrogateBoundaryDetectionIsExact() {
        let units = Array("a😀😀b".utf16)
        #expect(!MarkdownTextLines.splitsSurrogatePair(units, at: 0))
        #expect(!MarkdownTextLines.splitsSurrogatePair(units, at: 1))
        #expect(MarkdownTextLines.splitsSurrogatePair(units, at: 2))
        #expect(!MarkdownTextLines.splitsSurrogatePair(units, at: 3))
        #expect(MarkdownTextLines.splitsSurrogatePair(units, at: 4))
        #expect(!MarkdownTextLines.splitsSurrogatePair(units, at: 5))
        #expect(!MarkdownTextLines.splitsSurrogatePair(units, at: units.count))
        #expect(!MarkdownTextLines.splitsSurrogatePair([0xD83D], at: 1))
        #expect(!MarkdownTextLines.splitsSurrogatePair([0xD83D, 0x41], at: 1))
        #expect(!MarkdownTextLines.splitsSurrogatePair([0x41, 0xDE00], at: 1))
    }

    @Test
    func everyUTF16OffsetOfEveryDocumentEitherYieldsAWellFormedEditOrNone() {
        for text in Self.documents {
            let units = Array(text.utf16)
            for settings in Self.settingsVariants {
                for offset in 0...units.count {
                    let valid = Self.isValidInsertionPoint(units, offset)
                    let label = "\(text.debugDescription) @\(offset) \(settings)"
                    let outcomes = [
                        ("enter", MarkdownListEnter.edit(forEnterIn: units, caret: offset, settings: settings)),
                        (
                            "shift",
                            MarkdownListEnter.edit(forEnterIn: units, caret: offset, shift: true, settings: settings)
                        ),
                        ("backspace", MarkdownListEnter.edit(forBackspaceIn: units, caret: offset, settings: settings))
                    ]
                    for (name, edit) in outcomes {
                        guard let edit else { continue }
                        #expect(valid, "\(name) \(label)")
                        expectWellFormed(edit, in: text, "\(name) \(label)")
                    }
                }
            }
        }
    }

    @Test
    func listDocumentsEditAtEveryValidOffsetOfTheirLastItem() {
        let documents = ["- a\r\n- b", "1. a\r2. b", "- 😀 a\n- 😀 b"]
        for text in documents {
            let units = Array(text.utf16)
            let lastItemStart = units.lastIndex { $0 == 10 || $0 == 13 }.map { $0 + 1 } ?? 0
            for offset in (lastItemStart + 2)...units.count where Self.isValidInsertionPoint(units, offset) {
                #expect(
                    MarkdownListEnter.edit(forEnterIn: units, caret: offset) != nil,
                    "\(text.debugDescription) @\(offset)"
                )
            }
        }
    }
}
