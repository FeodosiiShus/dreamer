import Foundation
import Testing
@testable import Dreamder

struct MarkdownActionResultCoverage {
    @Test
    func minimalEditNeverSplitsSurrogatePairsSharingTheTrailingUnit() {
        let original: [UInt16] = [0x61, 0xD83D, 0xDE00, 0x62]
        let updated: [UInt16] = [0x61, 0xD83E, 0xDE00, 0x62]

        let edit = MarkdownActionResult.minimalEdit(from: original, to: updated)

        #expect(
            edit == MarkdownTextEdit(
                range: NSRange(location: 1, length: 2),
                replacement: String(decoding: [0xD83E, 0xDE00] as [UInt16], as: UTF16.self)
            )
        )
    }

    @Test
    func resultWithoutChangesHasNoEdits() {
        let buffer = MarkdownEditBuffer("same")

        let result = buffer.result(selections: [NSRange(location: 1, length: 0)])

        #expect(result.edits.isEmpty)
        #expect(result.text == "same")
    }
}

struct MarkdownEditBufferCoverage {
    @Test
    func replacementSwallowingASelectionBoundaryCollapsesItToTheReplacementEnd() {
        var buffer = MarkdownEditBuffer("abcdef")
        buffer.settle(NSRange(location: 2, length: 3))

        buffer.replace(1..<4, with: "XY")

        #expect(buffer.settled == [NSRange(location: 3, length: 1)])
        #expect(String(decoding: buffer.units, as: UTF16.self) == "aXYef")
    }

    @Test
    func settleFirstPrependsAndResultUsesSettledSelections() {
        var buffer = MarkdownEditBuffer(units: Array("ab".utf16))
        buffer.settle(NSRange(location: 2, length: 0))
        buffer.settleFirst(NSRange(location: 0, length: 1))
        buffer.insert("!", at: 2)

        let result = buffer.resultWithSettledSelections()

        #expect(buffer.length == 3)
        #expect(result.text == "ab!")
        #expect(result.selections == [NSRange(location: 0, length: 1), NSRange(location: 3, length: 0)])
    }
}
