import Testing
@testable import Dreamder

@Suite
struct NaturalCompareTests {
    @Test
    func numbersAreComparedByValue() {
        #expect("a2".naturalCompare("a10") < 0)
        #expect("a10".naturalCompare("a2") > 0)
        #expect("file9.txt".naturalCompare("file10.txt") < 0)
        #expect("v1.9".naturalCompare("v1.10") < 0)
        #expect("a1b2".naturalCompare("a1b10") < 0)
    }

    @Test
    func numbersWithMoreDigitsAreGreaterWithoutOverflow() {
        #expect("a99999999999999999999".naturalCompare("a100000000000000000000") < 0)
        #expect("a100000000000000000000".naturalCompare("a99999999999999999999") > 0)
    }

    @Test
    func leadingZerosOnlyBreakTies() {
        #expect("a007".naturalCompare("a7") > 0)
        #expect("a7".naturalCompare("a007") < 0)
        #expect("a007".naturalCompare("a8") < 0)
        #expect("a007".naturalCompare("a007") == 0)
    }

    @Test
    func equalStringsCompareEqual() {
        #expect("feature/login".naturalCompare("feature/login") == 0)
        #expect("".naturalCompare("") == 0)
    }

    @Test
    func caseIsIgnoredFirst() {
        #expect("a".naturalCompare("B") < 0)
        #expect("b".naturalCompare("A") > 0)
        #expect("Zebra".naturalCompare("apple") > 0)
        #expect("apple10".naturalCompare("Apple9") > 0)
    }

    @Test
    func caseBreaksTiesWhenTheLowerCasedStringsAreEqual() {
        #expect("A".naturalCompare("a") < 0)
        #expect("a".naturalCompare("A") > 0)
        #expect("Release".naturalCompare("release") < 0)
        #expect("a".naturalCompare("A", ignoreCase: false) > 0)
        #expect("a".naturalCompare("a", ignoreCase: false) == 0)
    }

    @Test
    func caseFoldingCoversNonAsciiLetters() {
        #expect("\u{E9}".naturalCompare("\u{C9}") > 0)
        #expect("\u{C9}".naturalCompare("\u{E9}") < 0)
        #expect("\u{E9}a".naturalCompare("\u{C9}b") < 0)
    }

    @Test
    func prefixesComeFirst() {
        #expect("abc".naturalCompare("abcd") < 0)
        #expect("abcd".naturalCompare("abc") > 0)
        #expect("feature".naturalCompare("feature/login") < 0)
        #expect("x".naturalCompare("x1") < 0)
        #expect("x1".naturalCompare("x") > 0)
        #expect("v1".naturalCompare("v1.0") < 0)
    }

    @Test
    func stringEndingInANumberIsLessThanOneContinuingAfterIt() {
        #expect("a1".naturalCompare("a1b") < 0)
        #expect("a1b".naturalCompare("a1") > 0)
        #expect("a10".naturalCompare("a1b") > 0)
    }

    @Test
    func sortingProducesHumanOrder() {
        let names = ["a10", "a2", "A1", "a1", "b", "a02", "B1"]
        let sorted = names.sorted { $0.isNaturallyOrdered(before: $1) }
        #expect(sorted == ["A1", "a1", "a2", "a02", "a10", "b", "B1"])
    }

    @Test
    func releaseBranchesSortByVersionNumber() {
        let names = ["release/1.10", "release/1.2", "release/1.9", "release/10.0", "release/2.0"]
        let sorted = names.sorted { $0.isNaturallyOrdered(before: $1) }
        #expect(sorted == ["release/1.2", "release/1.9", "release/1.10", "release/2.0", "release/10.0"])
    }

    @Test
    func likeFileNamesTreatsHyphenAsUnderscore() {
        #expect("a-b".naturalCompare("a.b") < 0)
        #expect("a-b".naturalCompare("a.b", likeFileNames: true) > 0)
        #expect("a-b".naturalCompare("a_b", likeFileNames: true) < 0)
        #expect("a_b".naturalCompare("a-b", likeFileNames: true) > 0)
    }

    @Test
    func spacesActAsNumberPadding() {
        #expect(" 5".naturalCompare("10") < 0)
        #expect("a 5".naturalCompare("a10") < 0)
    }

    @Test
    func isNaturallyOrderedMatchesTheSignOfNaturalCompare() {
        #expect("a2".isNaturallyOrdered(before: "a10"))
        #expect("a10".isNaturallyOrdered(before: "a2") == false)
        #expect("a".isNaturallyOrdered(before: "a") == false)
    }
}
