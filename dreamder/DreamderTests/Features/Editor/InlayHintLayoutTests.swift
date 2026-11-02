import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

@Suite
struct InlayHintLayoutTests {
    private func hint(_ label: TwoTypeOption<String, [InlayHintLabelPart]>, line: Int = 0, character: Int = 0) -> InlayHint {
        InlayHint(
            position: Position(line: line, character: character),
            label: label,
            kind: .type,
            textEdits: nil,
            tooltip: nil,
            paddingLeft: true,
            paddingRight: nil,
            data: nil
        )
    }

    @Test
    func labelDropsServerPaddingSpacesAndJoinsParts() {
        #expect(InlayHintLayout.label(of: hint(.optionA(" : Int "))) == ": Int")
        let parts = [
            InlayHintLabelPart(value: ": "),
            InlayHintLabelPart(value: "Array<"),
            InlayHintLabelPart(value: "String>")
        ]
        #expect(InlayHintLayout.label(of: hint(.optionB(parts))) == ": Array<String>")
    }

    @Test(arguments: [
        (0, Optional(10)),
        (3, Optional(13)),
        (5, Optional(15)),
        (6, nil),
        (-1, nil)
    ])
    func offsetStaysInsideTheLine(character: Int, expected: Int?) {
        let position = Position(line: 0, character: character)
        #expect(InlayHintLayout.offset(of: position, lineStart: 10, lineLength: 5) == expected)
    }

    @Test
    func pillWidthAddsPaddingAndMargins() {
        let attachment = InlayHintAttachment(text: ": Int", fontSize: 12)
        let empty = InlayHintAttachment(text: "", fontSize: 12)
        #expect(empty.width == InlayHintAttachment.horizontalPadding * 2 + InlayHintAttachment.margin * 2)
        #expect(attachment.width > empty.width)
    }
}
