import Testing
import Foundation
@testable import Dreamder

private func units(_ text: String) -> DiffUnits {
    Array(text.utf16)
}

@Suite struct TrimUtilCoverageTests {
    @Test func trimmingARangeSkipsSpacesTabsAndNewlinesOnBothEnds() {
        let text = units("  ab \t\n")

        #expect(TrimUtil.trim(text, 0, text.count) == (2, 4))
        #expect(TrimUtil.trim(text, 3, 5) == (3, 4))
    }

    @Test func trimmingABlankRangeCollapsesItAtItsEnd() {
        let text = units("a   b")

        #expect(TrimUtil.trim(text, 1, 4) == (4, 4))
        #expect(TrimUtil.trim(text, 2, 2) == (2, 2))
    }

    @Test func trimmingByPredicateSkipsIgnoredIndicesOnBothEnds() {
        let ignored: Set<Int> = [0, 1, 4]

        #expect(TrimUtil.trim(0, 5, ignored: { ignored.contains($0) }) == (2, 4))
        #expect(TrimUtil.trim(0, 2, ignored: { ignored.contains($0) }) == (2, 2))
    }

    @Test func codePointsCombineSurrogatePairsOnlyWhenTheyAreWellFormed() {
        let pair = units("\u{1F602}")

        #expect(TrimUtil.codePointAt(pair, 0) == 0x1F602)
        #expect(TrimUtil.codePointAt(pair, 1) == 0xDE02)
        #expect(TrimUtil.codePointAt([0xD83D], 0) == 0xD83D)
        #expect(TrimUtil.codePointAt([0xD83D, 0x0041], 0) == 0xD83D)
        #expect(TrimUtil.codePointAt([0x0041], 0) == 0x41)
        #expect(TrimUtil.charCount(0x1F602) == 2)
        #expect(TrimUtil.charCount(0x41) == 1)
    }

    @Test func loneSurrogatesCountAsContinuousScript() {
        #expect(TrimUtil.isContinuousScript(0xD800))
        #expect(TrimUtil.isContinuousScript(0xDFFF))
    }

    @Test func nonAsciiDigitsAreNotContinuousScript() {
        #expect(TrimUtil.isContinuousScript(0x0663) == false)
        #expect(TrimUtil.isContinuousScript(0x1D7D8) == false)
    }

    @Test func whitespaceCodePointsAreRecognisedOnlyInsideAscii() {
        #expect(TrimUtil.isWhiteSpaceCodePoint(32))
        #expect(TrimUtil.isWhiteSpaceCodePoint(9))
        #expect(TrimUtil.isWhiteSpaceCodePoint(10))
        #expect(TrimUtil.isWhiteSpaceCodePoint(13) == false)
        #expect(TrimUtil.isWhiteSpaceCodePoint(0xA0) == false)
        #expect(TrimUtil.isWhiteSpaceCodePoint(-1) == false)
    }

    @Test func threeWayWhitespaceExpansionStopsAtTheFirstSharedNonWhitespaceCharacter() {
        let text = units(" a ")

        let expanded = TrimUtil.expandWhitespaces(text, text, text, MergeRange(0, 3, 0, 3, 0, 3))

        #expect(expanded == MergeRange(1, 2, 1, 2, 1, 2))
    }

    @Test func threeWayWhitespaceExpansionStopsWhenOneSideDiffers() {
        let base = units("  x ")
        let left = units(" yx ")
        let right = units("  x ")

        let expanded = TrimUtil.expandWhitespaces(left, base, right, MergeRange(0, 4, 0, 4, 0, 4))

        #expect(expanded == MergeRange(1, 3, 1, 3, 1, 3))
        #expect(TrimUtil.expandWhitespacesForward(left, base, right, MergeRange(0, 4, 0, 4, 0, 4), endShift: 0) == 1)
        #expect(TrimUtil.expandWhitespacesForward(right, base, left, MergeRange(0, 4, 0, 4, 0, 4), endShift: 0) == 1)
        #expect(TrimUtil.expandWhitespacesBackward(left, base, right, MergeRange(0, 4, 0, 4, 0, 4)) == 1)
        #expect(TrimUtil.expandWhitespacesBackward(units("xy "), units("xy "), units("x  "), MergeRange(0, 3, 0, 3, 0, 3)) == 1)
    }

    @Test func twoWayWhitespaceExpansionStopsAtTheFirstSharedNonWhitespaceCharacter() {
        let text1 = units("  a  ")
        let text2 = units(" a   ")

        #expect(TrimUtil.expandWhitespaces(text1, text2, DiffRange(0, 5, 0, 5)) == DiffRange(1, 3, 1, 3))
        #expect(TrimUtil.expandWhitespacesForward(text1, text2, 0, 0, 5, 5) == 1)
        #expect(TrimUtil.expandWhitespacesBackward(text1, text2, 1, 1, 5, 5) == 2)
        #expect(TrimUtil.expandWhitespacesBackward(text1, text1, 0, 0, 5, 5) == 2)
    }

    @Test func rangeEqualityHelpersCompareTheSelectedSlices() {
        let text1 = units("ab cd")
        let text2 = units("xabcd")

        #expect(TrimUtil.isEquals(text1, text2, DiffRange(0, 2, 1, 3)))
        #expect(TrimUtil.isEquals(text1, text2, DiffRange(0, 2, 2, 4)) == false)
        #expect(TrimUtil.isEqualsIgnoreWhitespaces(text1, text2, DiffRange(0, 5, 1, 5)))
        #expect(TrimUtil.isEqualsIgnoreWhitespaces(text1, text2, DiffRange(0, 5, 0, 5)) == false)
    }

    @Test func threeWayRangeEqualityRequiresAllThreeSlicesToMatch() {
        let left = units("ab cd")
        let base = units("abcd")
        let right = units("ab  cd")

        #expect(TrimUtil.isEquals(base, base, base, MergeRange(0, 4, 0, 4, 0, 4)))
        #expect(TrimUtil.isEquals(left, base, base, MergeRange(0, 4, 0, 4, 0, 4)) == false)
        #expect(TrimUtil.isEquals(base, base, left, MergeRange(0, 4, 0, 4, 0, 4)) == false)
        #expect(TrimUtil.isEqualsIgnoreWhitespaces(left, base, right, MergeRange(0, 5, 0, 4, 0, 6)))
        #expect(TrimUtil.isEqualsIgnoreWhitespaces(left, base, base, MergeRange(0, 5, 0, 3, 0, 4)) == false)
        #expect(TrimUtil.isEqualsIgnoreWhitespaces(base, base, left, MergeRange(0, 4, 0, 4, 0, 3)) == false)
    }

    @Test func trimExpandSkipsIgnoredCharactersAndMatchesEqualOnes() {
        let text1 = units("xaby")
        let text2 = units("ab")
        let ignored1: Set<Int> = [0, 3]

        let range = TrimUtil.trimExpand(
            0,
            0,
            text1.count,
            text2.count,
            equals: { text1[$0] == text2[$1] },
            ignored1: { ignored1.contains($0) },
            ignored2: { _ in false }
        )

        #expect(range.isEmpty)
    }

    @Test func trimExpandLeavesTheDifferingMiddleBetweenIgnoredEnds() {
        let text1 = units("-aXb-")
        let text2 = units("aYb")
        let ignored1: Set<Int> = [0, 4]

        let range = TrimUtil.trimExpand(
            0,
            0,
            text1.count,
            text2.count,
            equals: { text1[$0] == text2[$1] },
            ignored1: { ignored1.contains($0) },
            ignored2: { _ in false }
        )

        #expect(range == DiffRange(2, 3, 1, 2))
    }

    @Test func trimExpandSkipsIgnoredCharactersOnTheSecondSideToo() {
        let text1 = units("ab")
        let text2 = units("-a-b-")
        let ignored2: Set<Int> = [0, 2, 4]

        let range = TrimUtil.trimExpand(
            0,
            0,
            text1.count,
            text2.count,
            equals: { text1[$0] == text2[$1] },
            ignored1: { _ in false },
            ignored2: { ignored2.contains($0) }
        )

        #expect(range.isEmpty)
    }

    @Test func expandingEqualEndsShrinksTheChangedRangeFromBothSides() {
        let text1 = units("abXcd")
        let text2 = units("abYYcd")

        let range = TrimUtil.expand(0, 0, text1.count, text2.count) { text1[$0] == text2[$1] }

        #expect(range == DiffRange(2, 3, 2, 4))
        #expect(TrimUtil.expandForward(0, 0, 5, 6) { text1[$0] == text2[$1] } == 2)
        #expect(TrimUtil.expandBackward(0, 0, 5, 6) { text1[$0] == text2[$1] } == 2)
    }
}
