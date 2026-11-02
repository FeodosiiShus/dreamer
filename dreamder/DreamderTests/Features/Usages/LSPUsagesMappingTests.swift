import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

@Suite("LSP usages mapping")
struct LSPUsagesMappingTests {
    private let firstURI = "file:///tmp/project/Sources/Model.swift"
    private let secondURI = "file:///tmp/project/Sources/Other.swift"

    private func location(
        _ uri: String,
        line: Int,
        start: Int,
        end: Int
    ) -> Location {
        Location(
            uri: uri,
            range: LSPRange(start: Position(line: line, character: start), end: Position(line: line, character: end))
        )
    }

    @Test func mapsLocations() {
        let locations = LSPUsagesMapping.locations(from: [location(firstURI, line: 3, start: 8, end: 11)])
        #expect(locations == [LSPReferenceLocation(
            uri: firstURI,
            line: 3,
            startCharacter: 8,
            endCharacter: 11
        )])
    }

    @Test func mapsMissingResponseToNoLocations() {
        #expect(LSPUsagesMapping.locations(from: nil).isEmpty)
    }

    @Test func sortsByPathThenLine() {
        let rows = LSPUsagesMapping.rows(
            from: [
                LSPReferenceLocation(uri: secondURI, line: 1, startCharacter: 4, endCharacter: 7),
                LSPReferenceLocation(uri: firstURI, line: 9, startCharacter: 2, endCharacter: 5),
                LSPReferenceLocation(uri: firstURI, line: 2, startCharacter: 6, endCharacter: 9)
            ],
            fileTexts: [:],
            workspacePath: "/tmp/project"
        )
        #expect(rows.map(\.fileName) == ["Model.swift", "Model.swift", "Other.swift"])
        #expect(rows.map(\.line) == [2, 9, 1])
    }

    @Test func mergesUsagesOnTheSameLine() {
        let rows = LSPUsagesMapping.rows(
            from: [
                LSPReferenceLocation(uri: firstURI, line: 4, startCharacter: 12, endCharacter: 17),
                LSPReferenceLocation(uri: firstURI, line: 4, startCharacter: 4, endCharacter: 9)
            ],
            fileTexts: [firstURI: "line0\nline1\nline2\nline3\nlet value = value + value\n"],
            workspacePath: "/tmp/project"
        )
        #expect(rows.count == 1)
        #expect(rows[0].column == 4)
        #expect(rows[0].lineText == "let value = value + value")
        #expect(rows[0].matchRange == NSRange(location: 4, length: 5))
    }

    @Test func keepsUsageCountAsRowCount() {
        let rows = LSPUsagesMapping.rows(
            from: [
                LSPReferenceLocation(uri: firstURI, line: 0, startCharacter: 0, endCharacter: 3),
                LSPReferenceLocation(uri: secondURI, line: 0, startCharacter: 0, endCharacter: 3)
            ],
            fileTexts: [firstURI: "abc\n", secondURI: "abc\n"],
            workspacePath: "/tmp/project"
        )
        #expect(rows.count == 2)
        #expect(rows[0].displayLine == 1)
    }

    @Test func derivesFileNameIconAndRelativeDirectory() {
        let rows = LSPUsagesMapping.rows(
            from: [LSPReferenceLocation(
                uri: "file:///tmp/project/Sources/Model/Thing.swift",
                line: 0,
                startCharacter: 0,
                endCharacter: 3
            )],
            fileTexts: [:],
            workspacePath: "/tmp/project"
        )
        #expect(rows[0].fileName == "Thing.swift")
        #expect(rows[0].fileIconName == "fileTypes/swiftLang")
        #expect(rows[0].relativeDirectory == "Sources/Model")
    }

    @Test func emptyRelativeDirectoryForWorkspaceRoot() {
        let rows = LSPUsagesMapping.rows(
            from: [LSPReferenceLocation(uri: "file:///tmp/project/Thing.swift", line: 0, startCharacter: 0, endCharacter: 1)],
            fileTexts: [:],
            workspacePath: "/tmp/project"
        )
        #expect(rows[0].relativeDirectory.isEmpty)
    }

    @Test func skipsNonFileLocations() {
        let rows = LSPUsagesMapping.rows(
            from: [LSPReferenceLocation(uri: "untitled:Untitled-1", line: 0, startCharacter: 0, endCharacter: 1)],
            fileTexts: [:],
            workspacePath: "/tmp/project"
        )
        #expect(rows.isEmpty)
    }

    @Test func trimsIndentationAndKeepsHighlight() {
        let display = LSPUsagesMapping.displayLine(
            from: Array("        let value = 1".utf16),
            startCharacter: 12,
            endCharacter: 17
        )
        #expect(display.text == "let value = 1")
        #expect(display.matchRange == NSRange(location: 4, length: 5))
    }

    @Test func highlightsWordForEmptyRange() {
        let display = LSPUsagesMapping.displayLine(
            from: Array("    print(value)".utf16),
            startCharacter: 10,
            endCharacter: 10
        )
        #expect(display.text == "print(value)")
        #expect(display.matchRange == NSRange(location: 6, length: 5))
    }

    @Test func highlightsWordWhenCaretSitsAtItsEnd() {
        let display = LSPUsagesMapping.displayLine(
            from: Array("\tvalue".utf16),
            startCharacter: 6,
            endCharacter: 6
        )
        #expect(display.text == "value")
        #expect(display.matchRange == NSRange(location: 0, length: 5))
    }

    @Test func missingLineHasNoHighlight() {
        let display = LSPUsagesMapping.displayLine(from: [], startCharacter: 4, endCharacter: 8)
        #expect(display.text.isEmpty)
        #expect(display.matchRange == nil)
    }

    @Test func stripsCarriageReturns() {
        let lines = LSPUsagesMapping.lineUnits(in: "one\r\ntwo\r\n")
        #expect(lines.map { String(decoding: $0, as: UTF16.self) } == ["one", "two", ""])
    }

    @Test func extractsSymbolAtCaret() {
        let line = "let result = calculate(value, other)"
        #expect(LSPUsagesMapping.symbol(inLine: line, character: 14) == "calculate")
        #expect(LSPUsagesMapping.symbol(inLine: line, character: 4) == "result")
        #expect(LSPUsagesMapping.symbol(inLine: line, character: 3) == "let")
    }

    @Test func extractsNoSymbolOutsideIdentifiers() {
        #expect(LSPUsagesMapping.symbol(inLine: "let a = 1 + 2", character: 5) == "a")
        #expect(LSPUsagesMapping.symbol(inLine: "   ", character: 1).isEmpty)
        #expect(LSPUsagesMapping.symbol(inLine: "", character: 0).isEmpty)
    }
}
