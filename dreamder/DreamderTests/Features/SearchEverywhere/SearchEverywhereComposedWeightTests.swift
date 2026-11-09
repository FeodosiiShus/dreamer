import Foundation
import Testing
@testable import Dreamder

@Suite
struct SearchEverywhereComposedWeightTests {
    private static let keyA = SearchEverywhereWeightKey(id: "a", order: 10, defaultWeight: 0)
    private static let keyB = SearchEverywhereWeightKey(id: "b", order: 20, defaultWeight: 5)
    private static let keyC = SearchEverywhereWeightKey(id: "c", order: 30, defaultWeight: 0)

    private func key(_ key: SearchEverywhereWeightKey?) throws -> SearchEverywhereWeightKey {
        try #require(key)
    }

    private func weight(
        _ match: Int,
        _ components: [(SearchEverywhereWeightKey?, Int)] = []
    ) throws -> SearchEverywhereComposedWeight {
        let extra = try components.map { SearchEverywhereWeightComponent(key: try key($0.0), weight: $0.1) }
        let matchComponent = SearchEverywhereWeightComponent(weight: match)
        return try #require(SearchEverywhereComposedWeight(components: [matchComponent] + extra))
    }

    private func assertCompare(
        _ expected: Int,
        _ left: SearchEverywhereComposedWeight,
        _ right: SearchEverywhereComposedWeight
    ) {
        #expect(left.compare(right).signum() == expected)
        #expect(right.compare(left).signum() == -expected)
    }

    @Test
    func matchDecidesBeforeOtherKeys() throws {
        let alpha = Self.keyA
        assertCompare(1, try weight(100, [(alpha, 0)]), try weight(50, [(alpha, 9)]))
    }

    @Test
    func missingComponentCountsAsDefaultWeight() throws {
        let alpha = Self.keyA
        let beta = Self.keyB
        assertCompare(0, try weight(100), try weight(100, [(alpha, 0)]))
        assertCompare(-1, try weight(100), try weight(100, [(alpha, 3)]))
        assertCompare(0, try weight(100), try weight(100, [(beta, 5)]))
        assertCompare(1, try weight(100), try weight(100, [(beta, 4)]))
    }

    @Test
    func keysAreComparedInTheirOrder() throws {
        let alpha = Self.keyA
        let beta = Self.keyB
        assertCompare(-1, try weight(100, [(alpha, 0), (beta, 9)]), try weight(100, [(alpha, 1), (beta, 0)]))
        assertCompare(1, try weight(100, [(beta, 6)]), try weight(100, [(alpha, 0), (beta, 5)]))
    }

    @Test
    func idDecidesTheOrderOfKeysWithTheSameOrder() throws {
        let first = SearchEverywhereWeightKey(id: "x", order: 10, defaultWeight: 0)
        let second = SearchEverywhereWeightKey(id: "y", order: 10, defaultWeight: 0)
        let built = try #require(SearchEverywhereComposedWeight(components: [
            SearchEverywhereWeightComponent(key: try key(second), weight: 0),
            SearchEverywhereWeightComponent(key: try key(first), weight: 0),
            SearchEverywhereWeightComponent(weight: 1)
        ]))

        #expect(built.components.map(\.key.id) == ["matchWeight", "x", "y"])
    }

    @Test
    func keysOfTheSameOrderCompareByIdInBothDirections() throws {
        let lower = try key(SearchEverywhereWeightKey(id: "x", order: 10, defaultWeight: 0))
        let higher = try key(SearchEverywhereWeightKey(id: "y", order: 10, defaultWeight: 0))

        #expect(lower.compare(higher) == -1)
        #expect(higher.compare(lower) == 1)
        #expect(lower.compare(lower) == 0)
        #expect(lower < higher)
        #expect(!(higher < lower))
    }

    @Test
    func keyEqualityAgreesWithComparison() throws {
        let copy = try key(SearchEverywhereWeightKey(id: "notDeprecated", order: 200, defaultWeight: 1))
        let shifted = try key(SearchEverywhereWeightKey(id: "notDeprecated", order: 201, defaultWeight: 1))

        #expect(SearchEverywhereWeightKey.notDeprecated == copy)
        #expect(SearchEverywhereWeightKey.notDeprecated.hashValue == copy.hashValue)
        #expect(SearchEverywhereWeightKey.notDeprecated.compare(copy) == 0)
        #expect(Set([SearchEverywhereWeightKey.notDeprecated]) == Set([copy]))
        #expect(SearchEverywhereWeightKey.notDeprecated != shifted)
    }

    @Test
    func notDeprecatedIsTheDefault() throws {
        let notDeprecated = SearchEverywhereWeightKey.notDeprecated
        assertCompare(0, try weight(100), try weight(100, [(notDeprecated, 1)]))
        assertCompare(1, try weight(100), try weight(100, [(notDeprecated, 0)]))
    }

    @Test
    func comparisonIsTransitive() throws {
        let alpha = Self.keyA
        let beta = Self.keyB
        let gamma = Self.keyC
        let keys = [alpha, beta, gamma]
        let values = [0, 1, 5, 9]
        var weights: [SearchEverywhereComposedWeight] = []
        for match in 0...1 {
            for mask in 0..<(1 << keys.count) {
                for value in values {
                    let chosen = keys.enumerated()
                        .filter { mask & (1 << $0.offset) != 0 }
                        .map { ($0.element, value) }
                    weights.append(try weight(match, chosen))
                }
            }
        }

        for first in weights {
            for second in weights {
                let firstSecond = first.compare(second).signum()
                #expect(-firstSecond == second.compare(first).signum())
                for third in weights {
                    let secondThird = second.compare(third).signum()
                    if firstSecond >= 0 && secondThird >= 0 {
                        #expect(first >= third)
                    }
                    if firstSecond == 0 {
                        #expect(first.compare(third).signum() == second.compare(third).signum())
                    }
                }
            }
        }
    }

    @Test
    func withAddsComponentInKeyOrderAndReplacesSameKey() throws {
        let alpha = Self.keyA
        let beta = Self.keyB
        let updated = try weight(100, [(beta, 1)])
            .with(SearchEverywhereWeightComponent(key: try key(alpha), weight: 2))
            .with(SearchEverywhereWeightComponent(key: try key(beta), weight: 7))

        #expect(updated.components.map(\.key.id) == ["matchWeight", "a", "b"])
        #expect(updated.components.map(\.weight) == [100, 2, 7])
    }

    @Test
    func withReplacingTheMatchComponentUpdatesTheFirstWeight() throws {
        let original = try weight(100, [(Self.keyA, 2)])
        let updated = original.with(SearchEverywhereWeightComponent(weight: 7))

        #expect(original.first == 100)
        #expect(updated.first == 7)
        #expect(updated.components.map(\.weight) == [7, 2])
        #expect(try weight(5).with(SearchEverywhereWeightComponent(key: try key(Self.keyA), weight: 1)).first == 5)
    }

    @Test
    func constructorRejectsInvalidComponents() throws {
        let alpha = try key(Self.keyA)
        #expect(SearchEverywhereComposedWeight(components: [
            SearchEverywhereWeightComponent(weight: 1),
            SearchEverywhereWeightComponent(key: alpha, weight: 0),
            SearchEverywhereWeightComponent(key: alpha, weight: 1)
        ]) == nil)
        let keyedOnly = [SearchEverywhereWeightComponent(key: alpha, weight: 0)]
        #expect(SearchEverywhereComposedWeight(components: keyedOnly) == nil)
        #expect(SearchEverywhereComposedWeight(components: []) == nil)
        #expect(SearchEverywhereWeightKey(id: "negative", order: -1, defaultWeight: 0) == nil)
        #expect(SearchEverywhereWeightKey(id: "matchWeight", order: 5, defaultWeight: 0) == nil)
    }

    @Test
    func firstIsTheMatchWeight() throws {
        #expect(try weight(42, [(Self.keyA, 9)]).first == 42)
    }
}
