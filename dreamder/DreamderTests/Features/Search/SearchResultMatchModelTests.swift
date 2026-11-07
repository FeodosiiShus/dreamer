import AppKit
import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite
struct SearchResultMatchModelTests {
    private static let boldFont = NSFont.systemFont(ofSize: 13, weight: .bold)
    private static let regularFont = NSFont.systemFont(ofSize: 13, weight: .regular)

    private func makeModel(
        line: String,
        keyword: String,
        file: CEWorkspaceFile = CEWorkspaceFile(url: URL(fileURLWithPath: "/tmp/a.swift"))
    ) throws -> SearchResultMatchModel {
        let keywordRange = try #require(line.range(of: keyword))
        return SearchResultMatchModel(
            rangeWithinFile: keywordRange,
            file: file,
            lineContent: line,
            keywordRange: keywordRange
        )
    }

    private func fontRuns(of label: NSAttributedString) -> [(range: NSRange, bold: Bool)] {
        var runs: [(range: NSRange, bold: Bool)] = []
        label.enumerateAttribute(
            .font,
            in: NSRange(location: 0, length: label.length)
        ) { value, range, _ in
            runs.append((range, (value as? NSFont) == Self.boldFont))
        }
        return runs
    }

    @Test
    func labelTextEqualsLineContent() throws {
        let model = try makeModel(line: "    let value = 42", keyword: "value")
        #expect(model.attributedLabel().string == "    let value = 42")
    }

    @Test
    func keywordInMiddleIsBoldBetweenTwoRegularRuns() throws {
        let model = try makeModel(line: "let value = 42", keyword: "value")
        let runs = fontRuns(of: model.attributedLabel())
        try #require(runs.count == 3)
        #expect(runs[0].range == NSRange(location: 0, length: 4))
        #expect(runs[0].bold == false)
        #expect(runs[1].range == NSRange(location: 4, length: 5))
        #expect(runs[1].bold)
        #expect(runs[2].range == NSRange(location: 9, length: 5))
        #expect(runs[2].bold == false)
    }

    @Test
    func keywordAtStartHasNoLeadingRegularRun() throws {
        let model = try makeModel(line: "import Foundation", keyword: "import")
        let runs = fontRuns(of: model.attributedLabel())
        try #require(runs.count == 2)
        #expect(runs[0].range == NSRange(location: 0, length: 6))
        #expect(runs[0].bold)
        #expect(runs[1].range == NSRange(location: 6, length: 11))
        #expect(runs[1].bold == false)
    }

    @Test
    func keywordAtEndHasNoTrailingRegularRun() throws {
        let model = try makeModel(line: "import Foundation", keyword: "Foundation")
        let runs = fontRuns(of: model.attributedLabel())
        try #require(runs.count == 2)
        #expect(runs[0].range == NSRange(location: 0, length: 7))
        #expect(runs[0].bold == false)
        #expect(runs[1].range == NSRange(location: 7, length: 10))
        #expect(runs[1].bold)
    }

    @Test
    func lineEqualToKeywordIsEntirelyBold() throws {
        let model = try makeModel(line: "needle", keyword: "needle")
        let runs = fontRuns(of: model.attributedLabel())
        try #require(runs.count == 1)
        #expect(runs[0].range == NSRange(location: 0, length: 6))
        #expect(runs[0].bold)
    }

    @Test
    func emptyKeywordRangeProducesNoBoldRun() {
        let line = "abc def"
        let position = line.index(line.startIndex, offsetBy: 3)
        let model = SearchResultMatchModel(
            rangeWithinFile: position..<position,
            file: CEWorkspaceFile(url: URL(fileURLWithPath: "/tmp/a.swift")),
            lineContent: line,
            keywordRange: position..<position
        )
        let label = model.attributedLabel()
        #expect(label.string == "abc def")
        #expect(fontRuns(of: label).allSatisfy { $0.bold == false })
    }

    @Test
    func boldRunUsesPrimaryColorAndRestUsesSecondary() throws {
        let model = try makeModel(line: "let value = 42", keyword: "value")
        let label = model.attributedLabel()
        #expect(label.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == .secondaryLabelColor)
        #expect(label.attribute(.foregroundColor, at: 4, effectiveRange: nil) as? NSColor == .labelColor)
        #expect(label.attribute(.foregroundColor, at: 9, effectiveRange: nil) as? NSColor == .secondaryLabelColor)
        #expect(label.attribute(.font, at: 0, effectiveRange: nil) as? NSFont == Self.regularFont)
        #expect(label.attribute(.font, at: 4, effectiveRange: nil) as? NSFont == Self.boldFont)
    }

    @Test
    func everyCharacterWrapsByCharacter() throws {
        let model = try makeModel(line: "let value = 42", keyword: "value")
        let label = model.attributedLabel()
        for location in [0, 4, 9] {
            let style = label.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
            #expect(style?.lineBreakMode == .byCharWrapping)
        }
    }

    @Test
    func boldRangeMatchesKeywordWithMultiScalarCharactersBefore() throws {
        let line = "🙂 é\u{301} match 🙂"
        let model = try makeModel(line: line, keyword: "match")
        let label = model.attributedLabel()
        let expected = NSRange(model.keywordRange, in: line)
        var effective = NSRange(location: 0, length: 0)
        let font = label.attribute(.font, at: expected.location, effectiveRange: &effective)
        #expect(font as? NSFont == Self.boldFont)
        #expect(effective == expected)
        #expect((label.string as NSString).substring(with: effective) == "match")
    }

    @Test
    func longLinesAreNotTruncatedByTheModel() throws {
        let prefix = String(repeating: "a", count: 200)
        let suffix = String(repeating: "z", count: 200)
        let model = try makeModel(line: prefix + "needle" + suffix, keyword: "needle")
        let label = model.attributedLabel()
        #expect(label.length == 406)
        let runs = fontRuns(of: label)
        #expect(runs.map(\.range) == [
            NSRange(location: 0, length: 200),
            NSRange(location: 200, length: 6),
            NSRange(location: 206, length: 200)
        ])
    }

    @Test
    func modelsAreIdentifiedByFreshUUIDs() throws {
        let first = try makeModel(line: "let value", keyword: "value")
        let second = try makeModel(line: "let value", keyword: "value")
        #expect(first.id != second.id)
        #expect(first == first)
        #expect(first != second)
    }

    @Test
    func equalityRequiresEveryStoredField() throws {
        let file = CEWorkspaceFile(url: URL(fileURLWithPath: "/tmp/a.swift"))
        let line = "let value = 42"
        let first = try makeModel(line: line, keyword: "value", file: file)
        let twin = try makeModel(line: line, keyword: "value", file: file)
        twin.id = first.id
        #expect(first == twin)
        #expect(first.hashValue == twin.hashValue)

        twin.keywordRange = line.startIndex..<line.index(line.startIndex, offsetBy: 3)
        #expect(first != twin)
        twin.keywordRange = first.keywordRange

        twin.rangeWithinFile = line.startIndex..<line.endIndex
        #expect(first != twin)
        twin.rangeWithinFile = first.rangeWithinFile

        twin.lineContent = "let value = 43"
        #expect(first != twin)
        twin.lineContent = first.lineContent

        twin.file = CEWorkspaceFile(url: URL(fileURLWithPath: "/tmp/b.swift"))
        #expect(first != twin)
        twin.file = file

        #expect(first == twin)
    }

    @Test
    func modelsWorkAsSetElements() throws {
        let first = try makeModel(line: "let value", keyword: "value")
        let second = try makeModel(line: "let value", keyword: "value")
        let set: Set<SearchResultMatchModel> = [first, second, first]
        #expect(set.count == 2)
        #expect(set.contains(first))
        #expect(set.contains(second))
    }
}
