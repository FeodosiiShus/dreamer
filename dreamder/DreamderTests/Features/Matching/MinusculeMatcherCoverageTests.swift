import Testing
@testable import Dreamder

struct MinusculeMatcherCoverageTests {
    private func matcher(_ pattern: String) -> MinusculeMatcher {
        MinusculeMatcher(pattern: pattern, mode: .ignoreCase, hardSeparators: "")
    }

    @Test
    func aLaterPatternLetterMustStartAWordInsideTheName() {
        #expect(!matcher("ab").matches("axbb"))
        #expect(matcher("ab").matches("a_b"))
    }

    @Test
    func aNonAsciiPatternLetterThatNeverStartsAWordIsNotFound() {
        #expect(!matcher("a\u{E9}").matches("ax\u{E9}"))
        #expect(matcher("a\u{E9}").matches("a_\u{E9}"))
    }

    @Test
    func matchingDegreeOfNoFragmentsIsZeroAndOfMissingFragmentsIsTheMinimum() {
        let core = MinusculeMatcherCore(pattern: "a", mode: .ignoreCase, hardSeparators: "")
        let name = Array("abc".utf16)

        #expect(core.matchingDegree(name, valueStartCaseMatch: false, fragments: []) == 0)
        #expect(core.matchingDegree(name, valueStartCaseMatch: false, fragments: nil) == Int.min)
    }

    @Test
    func aMatchReachingTheEndOfTheNameScoresHigherThanOneThatStopsEarlier() {
        let core = MinusculeMatcherCore(pattern: "c", mode: .ignoreCase, hardSeparators: "")
        let name = Array("abc".utf16)

        let atEnd = core.matchingDegree(name, valueStartCaseMatch: false, fragments: [2..<3])
        let early = core.matchingDegree(Array("abcd".utf16), valueStartCaseMatch: false, fragments: [2..<3])

        #expect(atEnd == early + 1)
    }
}
