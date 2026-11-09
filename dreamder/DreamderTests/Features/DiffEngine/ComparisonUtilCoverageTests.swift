import Testing
import Foundation
@testable import Dreamder

private func units(_ text: String) -> DiffUnits {
    Array(text.utf16)
}

@Suite struct ComparisonUtilCoverageTests {
    @Test func equalityHonoursEveryPolicy() {
        #expect(ComparisonUtil.isEquals(units("a b"), units("a b"), .default))
        #expect(ComparisonUtil.isEquals(units("a b"), units(" a b "), .default) == false)
        #expect(ComparisonUtil.isEquals(units("a b"), units(" a b "), .trimWhitespaces))
        #expect(ComparisonUtil.isEquals(units("a b"), units("a  b"), .trimWhitespaces) == false)
        #expect(ComparisonUtil.isEquals(units("a b"), units("a\tb "), .ignoreWhitespaces))
        #expect(ComparisonUtil.isEquals(units("a b"), units("a c"), .ignoreWhitespaces) == false)
    }

    @Test func equalTextsHonourEveryPolicyAndAcceptSlices() {
        let text = units("xa b y")

        #expect(ComparisonUtil.isEqualTexts(text[1..<4], units("a b")[...], .default))
        #expect(ComparisonUtil.isEqualTexts(text[1..<4], units(" a b")[...], .trimWhitespaces))
        #expect(ComparisonUtil.isEqualTexts(text[1..<4], units("ab")[...], .ignoreWhitespaces))
        #expect(ComparisonUtil.isEqualTexts(text[1..<4], units("ab")[...], .default) == false)
    }

    @Test func hashCodesAgreeWithTheEqualityOfEachPolicy() {
        let plain = units("ab")

        #expect(ComparisonUtil.hashCode(plain, .default) == 31 * 97 + 98)
        #expect(ComparisonUtil.hashCode(units("  ab\t"), .trimWhitespaces) == ComparisonUtil.hashCode(plain, .default))
        #expect(ComparisonUtil.hashCode(units(" a b\n"), .ignoreWhitespaces) == ComparisonUtil.hashCode(plain, .default))
        #expect(ComparisonUtil.hashCode(units(" a b"), .default) != ComparisonUtil.hashCode(units("a b"), .default))
        #expect(ComparisonUtil.hashCode([], .trimWhitespaces) == 0)
    }

    @Test func trimmedSliceKeepsItsOriginalIndices() {
        let text = units("  ab  ")

        let trimmed = ComparisonUtil.trimmed(text[...])

        #expect(trimmed.startIndex == 2)
        #expect(trimmed.endIndex == 4)
        #expect(ComparisonUtil.trimmed(units("   ")[...]).isEmpty)
    }

    @Test func trimmingPerLineComparesLineByLine() {
        #expect(ComparisonUtil.equalsTrimWhitespacesPerLine(units(" a \n b"), units("a\nb ")))
        #expect(ComparisonUtil.equalsTrimWhitespacesPerLine(units("a\nb"), units("a b")) == false)
        #expect(ComparisonUtil.equalsTrimWhitespacesPerLine(units("a\n"), units("a")) == false)
        #expect(ComparisonUtil.equalsTrimWhitespacesPerLine(units("a\nb"), units("a\nc")) == false)
        #expect(ComparisonUtil.equalsTrimWhitespacesPerLine([], []))
    }

    @Test func ignoringWhitespacesSkipsRunsOfBlanksOnEitherSide() {
        #expect(ComparisonUtil.equalsIgnoreWhitespaces(units("a \t\nb"), units("ab")))
        #expect(ComparisonUtil.equalsIgnoreWhitespaces(units("ab "), units("ab")))
        #expect(ComparisonUtil.equalsIgnoreWhitespaces(units("ab"), units(" ab")))
        #expect(ComparisonUtil.equalsIgnoreWhitespaces(units("ab"), units("ac")) == false)
        #expect(ComparisonUtil.equalsIgnoreWhitespaces(units("ab"), units("abc")) == false)
        #expect(ComparisonUtil.equalsIgnoreWhitespaces(units("abc"), units("ab")) == false)
    }
}
