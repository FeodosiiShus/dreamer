import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct ArrayIndexExtensionTests {
    @Test
    func secondAndThirdReturnTheElementsWhenPresent() {
        let values = [10, 20, 30, 40]
        #expect(values.second == 20)
        #expect(values.third == 30)
    }

    @Test
    func secondAndThirdAreNilWhenTheArrayIsTooShort() {
        #expect([Int]().second == nil)
        #expect([1].second == nil)
        #expect([1].third == nil)
        #expect([1, 2].third == nil)
        #expect([1, 2].second == 2)
    }
}

@MainActor
@Suite(.uiGate)
struct CollectionSafeSubscriptTests {
    @Test
    func inBoundsIndexReturnsTheElement() {
        let values = [1, 2, 3]
        #expect(values[safe: 0] == 1)
        #expect(values[safe: 2] == 3)
    }

    @Test
    func outOfBoundsIndexReturnsNil() {
        let values = [1, 2, 3]
        #expect(values[safe: 3] == nil)
        #expect(values[safe: -1] == nil)
        #expect([Int]()[safe: 0] == nil)
    }

    @Test
    func worksForStringsThroughTheirIndices() {
        let text = "abc"
        #expect(text[safe: text.startIndex] == "a")
        #expect(text[safe: text.endIndex] == nil)
    }
}
