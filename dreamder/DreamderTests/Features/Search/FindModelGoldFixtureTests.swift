import Foundation
import Testing
@testable import Dreamder

nonisolated struct FindGoldStage: Sendable, CustomStringConvertible {
    let id: String
    let findModel: FindModel
    let isGlobal: Bool
    let text: String
    let selection: Range<Int>?
    let expectedSpans: [Range<Int>]
    let nextStepText: String?

    var description: String { id }

    var searchRange: NSRange? {
        guard !isGlobal, let selection else { return nil }
        return NSRange(location: selection.lowerBound, length: selection.count)
    }

    var hasPattern: Bool { !findModel.stringToFind.isEmpty }
}

nonisolated enum FindGoldParser {
    static let directory = "platform/lang-impl/testData/editor/findInEditor"
    static let stageHeader = "--- FIND MODEL ---"
    static let stageFooter = "------------"
    static let separator = "--"
    static let previewPrefix = "Replacement Preview: "

    static func goldFileNames() throws -> [String] {
        try IntelliJTestData.files(in: directory, suffix: ".gold")
    }

    static func stageCount(in gold: String) -> Int {
        gold.components(separatedBy: stageHeader).count - 1
    }

    static func stages() throws -> [FindGoldStage] {
        try goldFileNames().flatMap { fileName in
            let gold = try IntelliJTestData.text("\(directory)/\(fileName)")
            return stages(in: gold, name: String(fileName.dropLast(".gold".count)))
        }
    }

    static func stages(in gold: String, name: String) -> [FindGoldStage] {
        var blocks: [[String]] = []
        var current: [String]?
        for line in gold.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line == stageHeader {
                current = []
            } else if line == stageFooter {
                if let finished = current { blocks.append(finished) }
                current = nil
            } else {
                current?.append(line)
            }
        }
        let parsed = blocks.compactMap(parse)
        return parsed.enumerated().map { index, stage in
            let next = index + 1 < parsed.count ? parsed[index + 1] : nil
            return stage.finalized(id: "\(name)#\(index + 1)", next: next)
        }
    }

    nonisolated struct ParsedStage {
        let findModel: FindModel
        let isGlobal: Bool
        let text: String
        let selection: Range<Int>?
        let expectedSpans: [Range<Int>]

        func finalized(id: String, next: ParsedStage?) -> FindGoldStage {
            var nextStepText: String?
            if let next,
               findModel.isReplaceState,
               next.findModel == findModel,
               next.isGlobal == isGlobal,
               next.text != text {
                nextStepText = next.text
            }
            return FindGoldStage(
                id: id,
                findModel: findModel,
                isGlobal: isGlobal,
                text: text,
                selection: selection,
                expectedSpans: expectedSpans,
                nextStepText: nextStepText
            )
        }
    }

    static func parse(_ lines: [String]) -> ParsedStage? {
        guard let modelEnd = lines.firstIndex(where: { $0.hasPrefix("userDataMap = ") }) else { return nil }
        var fields: [String: String] = [:]
        for line in lines[..<modelEnd] {
            guard let range = line.range(of: " = ") else { continue }
            fields[String(line[..<range.lowerBound])] = String(line[range.upperBound...])
        }

        var model = FindModel()
        model.stringToFind = quoted(fields["myStringToFind"]) ?? ""
        model.stringToReplace = quoted(fields["myStringToReplace"]) ?? ""
        model.isReplaceState = fields["isReplaceState"] == "true"
        model.isWholeWordsOnly = fields["isWholeWordsOnly"] == "true"
        model.isRegularExpressions = fields["isRegularExpressions"] == "true"
        model.isCaseSensitive = fields["isCaseSensitive"] == "true"

        var position = modelEnd + 1
        while position < lines.count, lines[position].isEmpty { position += 1 }
        guard position < lines.count, lines[position] == separator else { return nil }
        position += 1
        if position < lines.count, lines[position].hasPrefix(previewPrefix) {
            position += 1
            guard position < lines.count, lines[position] == separator else { return nil }
            position += 1
        }
        guard position < lines.count, lines[position].isEmpty else { return nil }
        let textStart = position + 1
        guard let textEnd = lines[textStart...].firstIndex(of: separator) else { return nil }
        let marked = lines[textStart..<textEnd].joined(separator: "\n")
        let (text, selection) = strip(marked)

        let spans = Set(lines[(textEnd + 1)...].compactMap(highlighterSpan))
            .sorted { ($0.lowerBound, $0.upperBound) < ($1.lowerBound, $1.upperBound) }

        return ParsedStage(
            findModel: model,
            isGlobal: fields["isGlobal"] == "true",
            text: text,
            selection: selection,
            expectedSpans: spans
        )
    }

    static func quoted(_ value: String?) -> String? {
        guard let value, value != "null", value.count >= 2 else { return nil }
        return String(value.dropFirst().dropLast())
    }

    private static let openBracket: UInt16 = 0x5B
    private static let closeBracket: UInt16 = 0x5D
    private static let lessThan: UInt16 = 0x3C
    private static let greaterThan: UInt16 = 0x3E

    static func strip(_ marked: String) -> (text: String, selection: Range<Int>?) {
        var units: [UInt16] = []
        var selectionStart: Int?
        var selectionEnd: Int?
        for unit in marked.utf16 {
            switch unit {
            case openBracket, closeBracket:
                continue
            case lessThan:
                selectionStart = units.count
            case greaterThan:
                selectionEnd = units.count
            default:
                units.append(unit)
            }
        }
        let selection = selectionStart.flatMap { start in selectionEnd.map { start..<$0 } }
        return (String(decoding: units, as: UTF16.self), selection)
    }

    static func highlighterSpan(_ line: String) -> Range<Int>? {
        let prefix = "highlighter: ("
        guard line.hasPrefix(prefix), let close = line.firstIndex(of: ")") else { return nil }
        let numbers = line[line.index(line.startIndex, offsetBy: prefix.count)..<close].split(separator: ",")
        guard numbers.count == 2, let start = Int(numbers[0]), let end = Int(numbers[1]) else { return nil }
        return start..<end
    }
}

@Suite
struct FindModelGoldFixtureTests {
    static let stages: [FindGoldStage] = (try? FindGoldParser.stages()) ?? []

    static let replacementStages: [FindGoldStage] = stages.filter {
        $0.findModel.isReplaceState && $0.hasPattern && !$0.expectedSpans.isEmpty
    }

    static let stepStages: [FindGoldStage] = stages.filter { $0.nextStepText != nil && !$0.expectedSpans.isEmpty }

    @Test
    func everyGoldStageIsParsed() throws {
        let names = try FindGoldParser.goldFileNames()
        #expect(names.count == 9)
        var expectedStageCount = 0
        for name in names {
            let gold = try IntelliJTestData.text("\(FindGoldParser.directory)/\(name)")
            expectedStageCount += FindGoldParser.stageCount(in: gold)
        }
        #expect(Self.stages.count == expectedStageCount)
        #expect(expectedStageCount > 0)
    }

    @Test(arguments: stages)
    func matchesAgreeWithIntelliJHighlighters(stage: FindGoldStage) {
        guard let regex = stage.findModel.compileMatcher() else {
            #expect(stage.expectedSpans.isEmpty)
            return
        }
        let matches = stage.findModel.findMatches(in: stage.text, using: regex, range: stage.searchRange)
        let spans = matches.map { $0.range.location..<($0.range.location + $0.range.length) }
        #expect(spans == stage.expectedSpans)
    }

    @Test(arguments: replacementStages)
    func replaceAllSubstitutesEveryHighlightedSpan(stage: FindGoldStage) throws {
        let regex = try #require(stage.findModel.compileMatcher())
        let result = try stage.findModel.replaceAll(in: stage.text, using: regex, range: stage.searchRange)

        var expected = stage.text as NSString
        for span in stage.expectedSpans.reversed() {
            expected = expected.replacingCharacters(
                in: NSRange(location: span.lowerBound, length: span.count),
                with: stage.findModel.stringToReplace
            ) as NSString
        }
        #expect(result.text == expected as String)
        #expect(result.replacedCount == stage.expectedSpans.count)
    }

    @Test(arguments: stepStages)
    func replacingFirstOccurrenceProducesTheNextStageDocument(stage: FindGoldStage) throws {
        let regex = try #require(stage.findModel.compileMatcher())
        let first = try #require(stage.expectedSpans.first)
        let match = try #require(
            stage.findModel.findMatches(in: stage.text, using: regex, range: stage.searchRange).first
        )
        let nsText = stage.text as NSString
        let replacement = try stage.findModel.replacement(for: match, in: nsText, using: regex)
        let replaced = nsText.replacingCharacters(
            in: NSRange(location: first.lowerBound, length: first.count),
            with: replacement
        )
        #expect(replaced == stage.nextStepText)
    }
}
