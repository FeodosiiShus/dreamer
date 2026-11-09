import Foundation
import Testing
@testable import Dreamder

@Suite("LSP completion ranking")
struct LSPCompletionRankingTests {
    private func input(
        _ label: String,
        prefix: String = "",
        sortText: String? = nil,
        filterText: String? = nil,
        preselect: Bool = false
    ) -> LSPCompletionRankingInput {
        LSPCompletionRankingInput(
            filterText: filterText ?? label,
            label: label,
            sortText: sortText,
            preselect: preselect,
            prefix: prefix
        )
    }

    private func labels(_ inputs: [LSPCompletionRankingInput]) -> [String] {
        LSPCompletionRanking.order(inputs).map { inputs[$0].label }
    }

    @Test func withoutAPrefixEverythingStaysAndSortsBySortTextThenLabel() {
        let inputs = [
            input("zeta", sortText: "02"),
            input("alpha", sortText: "01"),
            input("beta", sortText: "01"),
            input("fallback")
        ]
        #expect(labels(inputs) == ["alpha", "beta", "zeta", "fallback"])
    }

    @Test func sortTextBeatsTheMatchingDegree() {
        let inputs = [
            input("foo", prefix: "foo", sortText: "2"),
            input("fooBar", prefix: "foo", sortText: "1")
        ]
        #expect(labels(inputs) == ["fooBar", "foo"])
    }

    @Test func itemsWithoutSortTextFollowTheExplicitOnes() {
        let inputs = [
            input("foo", prefix: "foo"),
            input("fooBar", prefix: "foo", sortText: "9")
        ]
        #expect(labels(inputs) == ["fooBar", "foo"])
    }

    @Test func theMatchingDegreeOrdersEqualSortTexts() {
        let inputs = [
            input("fooBaz", prefix: "foo", sortText: "1"),
            input("foo", prefix: "foo", sortText: "1"),
            input("fooBar", prefix: "foo", sortText: "1")
        ]
        #expect(labels(inputs) == ["foo", "fooBar", "fooBaz"])
    }

    @Test func equalDegreesFallBackToTheLabelAndThenTheOriginalOrder() {
        let inputs = [
            input("fooB", prefix: "foo"),
            input("fooA", prefix: "foo"),
            input("fooA", prefix: "foo")
        ]
        #expect(LSPCompletionRanking.order(inputs) == [1, 2, 0])
    }

    @Test func nonMatchingItemsAreFilteredOut() {
        let inputs = [input("bar", prefix: "foo"), input("foo", prefix: "foo")]
        #expect(labels(inputs) == ["foo"])
    }

    @Test func camelHumpPrefixesMatch() {
        let inputs = [input("getFooBar", prefix: "gFB"), input("getBar", prefix: "gFB")]
        #expect(labels(inputs) == ["getFooBar"])
    }

    @Test func matchingIsCaseInsensitive() {
        let inputs = [input("Private", prefix: "pri"), input("print", prefix: "pri")]
        #expect(Set(labels(inputs)) == ["Private", "print"])
    }

    @Test func theFilterTextDecidesWhetherAnItemMatches() {
        let inputs = [input("", prefix: "prev", filterText: "preview"), input("other", prefix: "prev")]
        #expect(LSPCompletionRanking.order(inputs) == [0])
    }

    @Test func eachItemCarriesItsOwnPrefix() {
        let inputs = [input("alpha", prefix: "al"), input("beta", prefix: "al"), input("beta2", prefix: "be")]
        #expect(labels(inputs) == ["alpha", "beta2"])
    }

    @Test func aPreselectedItemMovesToTheFront() {
        let inputs = [
            input("foo", prefix: "foo", sortText: "1"),
            input("fooBar", prefix: "foo", sortText: "2", preselect: true),
            input("fooBaz", prefix: "foo", sortText: "3", preselect: true)
        ]
        #expect(labels(inputs) == ["fooBar", "foo", "fooBaz"])
    }

    @Test func aPreselectedItemThatIsAlreadyFirstStaysAndOneThatDoesNotMatchIsIgnored() {
        let first = [
            input("foo", prefix: "foo", sortText: "1", preselect: true),
            input("fooBar", prefix: "foo", sortText: "2")
        ]
        #expect(labels(first) == ["foo", "fooBar"])
        let filtered = [
            input("foo", prefix: "foo", sortText: "1"),
            input("zzz", prefix: "foo", sortText: "0", preselect: true)
        ]
        #expect(labels(filtered) == ["foo"])
    }

    @Test func emptyInputYieldsNothing() {
        #expect(LSPCompletionRanking.order([]).isEmpty)
    }
}
