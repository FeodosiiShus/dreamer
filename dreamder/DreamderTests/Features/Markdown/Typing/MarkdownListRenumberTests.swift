import Foundation
import Testing
@testable import Dreamder

nonisolated struct MarkdownNumberingCase: Sendable, CustomTestStringConvertible {
    let type: MarkdownListNumberingType
    let before: String
    let after: String

    init(_ type: MarkdownListNumberingType, _ before: String, _ after: String) {
        self.type = type
        self.before = before
        self.after = after
    }

    var testDescription: String {
        "\(type): \(before.debugDescription)"
    }
}


nonisolated struct MarkdownRenumberCase: Sendable, CustomTestStringConvertible {
    let name: String
    let before: String
    let after: String
    let recursive: Bool
    let restart: Bool
    let sequentially: Bool

    init(
        _ name: String,
        _ before: String,
        _ after: String,
        recursive: Bool = false,
        restart: Bool = false,
        sequentially: Bool = true
    ) {
        self.name = name
        self.before = before
        self.after = after
        self.recursive = recursive
        self.restart = restart
        self.sequentially = sequentially
    }

    var testDescription: String {
        name
    }
}

@Suite
struct MarkdownListRenumberTests {
    static let cases: [MarkdownRenumberCase] = [
        .init("sequential from the first number", "1. a<caret>\n1. b\n1. c", "1. a<caret>\n2. b\n3. c"),
        .init("sequential keeps a non one start", "5. a<caret>\n1. b\n1. c", "5. a<caret>\n6. b\n7. c"),
        .init("all ones", "1. a<caret>\n2. b\n3. c", "1. a<caret>\n1. b\n1. c", sequentially: false),
        .init("restart numbering", "5. a<caret>\n7. b", "1. a<caret>\n2. b", restart: true),
        .init("without restart", "5. a<caret>\n7. b", "5. a<caret>\n6. b"),
        .init("closing parenthesis delimiter is kept", "1) a<caret>\n3) b", "1) a<caret>\n2) b"),
        .init("already correct list is untouched", "1. a<caret>\n2. b", "1. a<caret>\n2. b"),
        .init("bullets are not numbered", "- a<caret>\n- b", "- a<caret>\n- b"),
        .init("caret on a later item renumbers the same list", "1. a\n1. b\n1. c<caret>", "1. a\n2. b\n3. c<caret>"),
        .init(
            "children shift when the marker gets wider",
            "9. a<caret>\n   - x\n9. b\n   - y",
            "9. a<caret>\n   - x\n10. b\n    - y"
        ),
        .init(
            "non recursive leaves sublists numbering alone",
            "1. a<caret>\n   1. x\n   1. y\n1. b",
            "1. a<caret>\n   1. x\n   1. y\n2. b"
        ),
        .init(
            "recursive restarts every sublist",
            "1. a<caret>\n   1. x\n   1. y\n1. b\n   5. z\n   9. w",
            "1. a<caret>\n   1. x\n   2. y\n2. b\n   1. z\n   2. w",
            recursive: true
        ),
        .init(
            "recursive recomputes nested indents",
            "9. a<caret>\n   - x\n9. b\n   1. y\n   1. z",
            "9. a<caret>\n   - x\n10. b\n    1. y\n    2. z",
            recursive: true
        ),
        .init(
            "recursive with ones in the top list keeps sublists sequential",
            "1. a<caret>\n   1. x\n   1. y\n2. b",
            "1. a<caret>\n   1. x\n   2. y\n1. b",
            recursive: true,
            sequentially: false
        ),
        .init("inside a block quote", "> 1. a<caret>\n> 1. b", "> 1. a<caret>\n> 2. b"),
        .init("indented list keeps its indent", "  1. a<caret>\n  1. b", "  1. a<caret>\n  2. b"),
        .init(
            "continuation lines of an item follow its marker width",
            "9. a<caret>\n9. b\n   text",
            "9. a<caret>\n10. b\n    text"
        ),
        .init("two lists separated by a paragraph are independent", "1. a<caret>\n1. b\n\npara\n\n1. c", "1. a<caret>\n2. b\n\npara\n\n1. c"),
        .init("different delimiter starts another list", "1. a<caret>\n1. b\n1) c", "1. a<caret>\n2. b\n1) c")
    ]

    @Test(arguments: cases)
    func renumbers(_ scenario: MarkdownRenumberCase) {
        let result = MarkdownTypingHarness.renumber(
            scenario.before,
            recursive: scenario.recursive,
            restart: scenario.restart,
            sequentially: scenario.sequentially
        )
        #expect(result == scenario.after)
    }

    @Test
    func renumberOutsideAListChangesNothing() {
        #expect(MarkdownTypingHarness.renumber("para<caret>", recursive: true, restart: true) == "para<caret>")
    }

    @Test
    func enterRenumbersTheWholeListWhenEnabled() {
        let settings = MarkdownTypingSettings(renumberListsOnType: true)
        let result = MarkdownTypingHarness.enter("1. a\n1. b<caret>\n1. c", settings: settings)
        #expect(result == "1. a\n2. b\n3. <caret>\n4. c")
    }

    @Test
    func enterRenumbersWithOnesWhenEnabled() {
        let settings = MarkdownTypingSettings(renumberListsOnType: true, listNumberingType: .ones)
        let result = MarkdownTypingHarness.enter("1. a\n2. b<caret>\n3. c", settings: settings)
        #expect(result == "1. a\n1. b\n1. <caret>\n1. c")
    }

    @Test
    func enterWidensFollowingContentWhenRenumberingCrossesTen() {
        let settings = MarkdownTypingSettings(renumberListsOnType: true)
        let result = MarkdownTypingHarness.enter("9. a<caret>\n   text\n10. b", settings: settings)
        #expect(result == "9. a\n10. <caret>\n    text\n11. b")
    }

    @Test
    func unindentingEmptyNestedItemRenumbersWhenEnabled() {
        let settings = MarkdownTypingSettings(renumberListsOnType: true)
        let result = MarkdownTypingHarness.enter("1. a\n   1. b\n2. c\n   1. <caret>", settings: settings)
        #expect(result == "1. a\n   1. b\n2. c\n3. <caret>")
    }

    static let previousItemBasedCases: [MarkdownTypingCase] = [
        .init("simple list", "1. First item<caret>", "1. First item\n2. <caret>"),
        .init("incorrect numbering", "1. First item\n42. Second item<caret>", "1. First item\n42. Second item\n43. <caret>"),
        .init(
            "sublist of ones",
            "1. Some item\n   1. Some item\n      1. Some item\n      1. Some item<caret>\n   1. Some item\n1. Some item",
            "1. Some item\n   1. Some item\n      1. Some item\n      1. Some item\n      2. <caret>\n   1. Some item\n1. Some item"
        ),
        .init("zero based list", "0. zero<caret>", "0. zero\n1. <caret>")
    ]

    @Test(arguments: previousItemBasedCases)
    func newItemFollowsPreviousItemNumber(_ scenario: MarkdownTypingCase) {
        #expect(MarkdownTypingHarness.enter(scenario.before) == scenario.after)
    }

    static let numberingTypeCases: [MarkdownNumberingCase] = [
        .init(.sequential, "1. a\n2. b<caret>", "1. a\n2. b\n3. <caret>"),
        .init(.ones, "1. a\n2. b<caret>", "1. a\n2. b\n1. <caret>"),
        .init(.previousNumber, "1. a\n2. b<caret>", "1. a\n2. b\n2. <caret>"),
        .init(.previousNumber, "7. a<caret>", "7. a\n7. <caret>")
    ]

    @Test(arguments: numberingTypeCases)
    func numberingTypeDecidesTheNewItemNumber(_ scenario: MarkdownNumberingCase) {
        let settings = MarkdownTypingSettings(listNumberingType: scenario.type)
        #expect(MarkdownTypingHarness.enter(scenario.before, settings: settings) == scenario.after)
    }

    @Test
    func previousNumberTypeIgnoresRenumberOnType() {
        let settings = MarkdownTypingSettings(renumberListsOnType: true, listNumberingType: .previousNumber)
        let result = MarkdownTypingHarness.enter("1. a\n5. b<caret>\n9. c", settings: settings)
        #expect(result == "1. a\n5. b\n5. <caret>\n9. c")
    }
}
