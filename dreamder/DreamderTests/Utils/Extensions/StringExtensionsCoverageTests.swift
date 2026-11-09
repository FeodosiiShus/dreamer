import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct StringRangesTests {
    private func offsets(_ text: String, _ ranges: [Range<String.Index>]) -> [Range<Int>] {
        ranges.map { text.distance(from: text.startIndex, to: $0.lowerBound)
            ..< text.distance(from: text.startIndex, to: $0.upperBound) }
    }

    @Test
    func findsAllNonOverlappingRanges() {
        let text = "abcabcabc"
        #expect(offsets(text, text.ranges(of: "bc", options: [])) == [1..<3, 4..<6, 7..<9])
        #expect(offsets("aaaa", "aaaa".ranges(of: "aa", options: [])) == [0..<2, 2..<4])
    }

    @Test
    func honoursCompareOptions() {
        let text = "Foo foo FOO"
        #expect(text.ranges(of: "foo", options: []).count == 1)
        #expect(text.ranges(of: "foo", options: .caseInsensitive).count == 3)
    }

    @Test
    func honoursTheLocale() {
        let text = "stra\u{DF}e STRASSE"
        let ranges = text.ranges(of: "strasse", options: .caseInsensitive, locale: Locale(identifier: "de_DE"))
        #expect(ranges.count >= 1)
    }

    @Test
    func noMatchOrEmptyNeedleGivesNoRanges() {
        #expect("abc".ranges(of: "x", options: []).isEmpty)
        #expect("abc".ranges(of: "", options: []).isEmpty)
        #expect("".ranges(of: "a", options: []).isEmpty)
    }

    @Test
    func worksOnSubstrings() {
        let text = "xx abab"
        let tail = text.dropFirst(3)
        #expect(tail.ranges(of: "ab", options: []).count == 2)
    }
}

@MainActor
@Suite(.uiGate)
struct StringHighlightOccurrencesTests {
    private func snapshot(_ content: some View) async throws -> NSBitmapImageRep? {
        let hosted = HostedViewFixture.host(size: NSSize(width: 240, height: 60)) {
            content.padding(8).frame(width: 240, height: 60, alignment: .leading)
        }
        defer { hosted.close() }
        try await hosted.settle(.milliseconds(100))
        return hosted.snapshot()
    }

    @Test
    func emptySearchReturnsThePlainText() async throws {
        let plain = try await snapshot(Text("Hello World"))
        let highlighted = try await snapshot("Hello World".highlightOccurrences(""))

        #expect(!HostedView.pixelsDiffer(plain, highlighted))
    }

    @Test
    func matchesAreRenderedDifferentlyFromThePlainText() async throws {
        let plain = try await snapshot(Text("Hello World"))
        let highlighted = try await snapshot("Hello World".highlightOccurrences("o"))

        #expect(HostedView.pixelsDiffer(plain, highlighted))
    }

    @Test
    func searchIsCaseInsensitiveAndKeepsTheOriginalCasing() async throws {
        let lower = try await snapshot("Hello World".highlightOccurrences("world"))
        let upper = try await snapshot("Hello World".highlightOccurrences("WORLD"))

        #expect(!HostedView.pixelsDiffer(lower, upper))
    }

    @Test
    func searchWithoutMatchesStillRendersTheWholeText() async throws {
        let none = try await snapshot("Hello World".highlightOccurrences("zzz"))
        let matching = try await snapshot("Hello World".highlightOccurrences("Hello"))

        #expect(HostedView.pixelsDiffer(none, matching))
    }
}

@MainActor
@Suite(.uiGate)
struct NaturalCompareCoverageTests {
    @Test
    func likeFileNamesComparesAHyphenOnTheRightAsAnUnderscore() {
        #expect("a.b".naturalCompare("a-b", likeFileNames: true) < 0)
        #expect("a-b".naturalCompare("a.b", likeFileNames: true) > 0)
        #expect("a_b".naturalCompare("a-b", likeFileNames: true) > 0)
        #expect("a-b".naturalCompare("a_b", likeFileNames: true) < 0)
    }

    @Test
    func caseFoldingOrdersDistinctNonAsciiUppercaseLetters() {
        #expect("\u{C9}".naturalCompare("\u{C8}") > 0)
        #expect("\u{C8}".naturalCompare("\u{C9}") < 0)
        #expect("\u{E9}".naturalCompare("\u{E8}") > 0)
    }

    @Test
    func caseFoldingKeepsUnitsWithoutASimpleMapping() {
        #expect("\u{1F600}".naturalCompare("\u{1F601}") < 0)
        #expect("\u{1F601}".naturalCompare("\u{1F600}") > 0)
        #expect("\u{DF}".naturalCompare("b") > 0)
        #expect("b".naturalCompare("\u{DF}") < 0)
    }

    @Test
    func spaceSortsAfterPunctuationBelowDigits() {
        #expect("a b".naturalCompare("a!b") > 0)
        #expect("a!b".naturalCompare("a b") < 0)
    }
}
