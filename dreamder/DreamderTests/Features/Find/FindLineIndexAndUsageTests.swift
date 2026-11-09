import Foundation
import Testing
@testable import Dreamder

@Suite
struct FindLineIndexAndUsageTests {
    private func usages(
        in text: String,
        find: String,
        replace: String = "",
        withReplacement: Bool = true,
        configure: (inout FindModel) -> Void = { _ in }
    ) throws -> [FindUsage] {
        var model = FindModel()
        model.stringToFind = find
        model.stringToReplace = replace
        configure(&model)
        let regex = try #require(model.compileMatcher())
        let lines = FindLineIndex(text)
        let source = text as NSString
        return model.findMatches(in: text, using: regex).map {
            FindUsage.make(
                for: $0,
                in: source,
                lines: lines,
                model: model,
                regex: regex,
                withReplacement: withReplacement
            )
        }
    }

    @Test
    func positionsOnTheFirstLineAreOneBased() {
        let index = FindLineIndex("ab\ncd")
        #expect(index.position(of: 0) == FindTextPosition(line: 1, column: 1))
        #expect(index.position(of: 2) == FindTextPosition(line: 1, column: 3))
    }

    @Test
    func positionsAfterALineFeedStartTheNextLine() {
        let index = FindLineIndex("ab\ncd\nef")
        #expect(index.position(of: 3) == FindTextPosition(line: 2, column: 1))
        #expect(index.position(of: 5) == FindTextPosition(line: 2, column: 3))
        #expect(index.position(of: 6) == FindTextPosition(line: 3, column: 1))
    }

    @Test
    func carriageReturnStaysInsideTheLineAndOnlyLineFeedBreaks() {
        let index = FindLineIndex("a\r\nb")
        #expect(index.position(of: 1) == FindTextPosition(line: 1, column: 2))
        #expect(index.position(of: 2) == FindTextPosition(line: 1, column: 3))
        #expect(index.position(of: 3) == FindTextPosition(line: 2, column: 1))
    }

    @Test
    func emptyTextHasOneLine() {
        let index = FindLineIndex("")
        #expect(index.position(of: 0) == FindTextPosition(line: 1, column: 1))
    }

    @Test
    func offsetAtTheEndOfTextAfterATrailingNewlineIsOnTheNextLine() {
        let index = FindLineIndex("ab\n")
        #expect(index.position(of: 3) == FindTextPosition(line: 2, column: 1))
        let flat = FindLineIndex("ab")
        #expect(flat.position(of: 2) == FindTextPosition(line: 1, column: 3))
    }

    @Test
    func columnsCountUTF16UnitsForAstralCharacters() {
        let index = FindLineIndex("😀a\nb😀c")
        #expect(index.position(of: 1) == FindTextPosition(line: 1, column: 2))
        #expect(index.position(of: 2) == FindTextPosition(line: 1, column: 3))
        #expect(index.position(of: 4) == FindTextPosition(line: 2, column: 1))
        #expect(index.position(of: 7) == FindTextPosition(line: 2, column: 4))
    }

    @Test
    func usageWithoutReplacementCarriesRangeAndPositions() throws {
        let found = try usages(in: "x\nfoo foo", find: "foo", replace: "bar", withReplacement: false)
        #expect(found.count == 2)
        let first = try found.required(at: 0)
        let second = try found.required(at: 1)
        #expect(first.range == NSRange(location: 2, length: 3))
        #expect(first.replacement == nil)
        #expect(first.start == FindTextPosition(line: 2, column: 1))
        #expect(first.end == FindTextPosition(line: 2, column: 4))
        #expect(second.start == FindTextPosition(line: 2, column: 5))
        #expect(second.end == FindTextPosition(line: 2, column: 8))
    }

    @Test
    func usageWithReplacementUsesThePlainReplacementText() throws {
        let found = try usages(in: "foo", find: "foo", replace: "bar")
        #expect(found.map(\.replacement) == ["bar"])
    }

    @Test
    func regexGroupsExpandInTheReplacement() throws {
        let found = try usages(in: "key=42 name=7", find: "(\\w+)=(\\d+)", replace: "$2=$1") {
            $0.isRegularExpressions = true
        }
        #expect(found.map(\.replacement) == ["42=key", "7=name"])
    }

    @Test
    func caseConversionEscapesApplyToGroups() throws {
        let found = try usages(in: "key=42", find: "(\\w+)=(\\d+)", replace: "\\U$1\\E=$2") {
            $0.isRegularExpressions = true
        }
        #expect(found.map(\.replacement) == ["KEY=42"])
    }

    @Test
    func preserveCaseFollowsTheMatchedText() throws {
        let found = try usages(in: "Foo FOO foo", find: "foo", replace: "bar") {
            $0.isPreserveCase = true
        }
        #expect(found.map(\.replacement) == ["Bar", "BAR", "bar"])
    }

    @Test
    func templateErrorLeavesTheReplacementNil() throws {
        let found = try usages(in: "aa", find: "(a)", replace: "$5") {
            $0.isRegularExpressions = true
        }
        #expect(found.count == 2)
        #expect(found.allSatisfy { $0.replacement == nil })
        #expect(try found.required(at: 0).range == NSRange(location: 0, length: 1))
    }

    @Test
    func multiLineMatchEndsOnALaterLine() throws {
        let found = try usages(in: "ab\ncd\nef", find: "b\ncd\ne", withReplacement: false)
        #expect(found.count == 1)
        let usage = try found.required(at: 0)
        #expect(usage.range == NSRange(location: 1, length: 6))
        #expect(usage.start == FindTextPosition(line: 1, column: 2))
        #expect(usage.end == FindTextPosition(line: 3, column: 2))
    }

    @Test
    func movedShiftsTheRangeAndRecomputesPositions() throws {
        let found = try usages(in: "foo\nfoo", find: "foo", replace: "x")
        let second = try found.required(at: 1)
        let moved = second.moved(by: 3, lines: FindLineIndex("foobar\nfoo"))
        #expect(moved.range == NSRange(location: 7, length: 3))
        #expect(moved.replacement == "x")
        #expect(moved.start == FindTextPosition(line: 2, column: 1))
        #expect(moved.end == FindTextPosition(line: 2, column: 4))
    }

    @Test
    func movedBackwardsCanChangeTheLine() throws {
        let found = try usages(in: "a\nb\nfoo", find: "foo", withReplacement: false)
        let moved = try found.required(at: 0).moved(by: -2, lines: FindLineIndex("a\nfoo"))
        #expect(moved.range == NSRange(location: 2, length: 3))
        #expect(moved.replacement == nil)
        #expect(moved.start == FindTextPosition(line: 2, column: 1))
        #expect(moved.end == FindTextPosition(line: 2, column: 4))
    }
}
