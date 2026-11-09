import Foundation
import Testing
@testable import Dreamder

private struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

struct SequencePair: Sendable, CustomTestStringConvertible {
    let first: [Int]
    let second: [Int]

    init(_ first: [Int], _ second: [Int]) {
        self.first = first
        self.second = second
    }

    var testDescription: String { "\(first) vs \(second)" }
}

private func bruteForceLCSLength<T: Equatable>(_ first: [T], _ second: [T]) -> Int {
    var previous = [Int](repeating: 0, count: second.count + 1)
    for x in first {
        var current = [Int](repeating: 0, count: second.count + 1)
        for (index, y) in second.enumerated() {
            current[index + 1] = x == y ? previous[index] + 1 : max(previous[index + 1], current[index])
        }
        previous = current
    }
    return previous[second.count]
}

private func randomSequence(length: Int, alphabet: Int, using generator: inout SplitMix64) -> [Int] {
    (0..<length).map { _ in Int.random(in: 0..<alphabet, using: &generator) }
}

private func bits(_ set: DiffBitSet, _ count: Int) -> [Int] {
    (0..<count).map { set[$0] ? 1 : 0 }
}

private func markedCount(_ set: DiffBitSet, _ count: Int) -> Int {
    bits(set, count).reduce(0, +)
}

private func expectBits(
    _ set: DiffBitSet,
    _ expected: [Int],
    sourceLocation: SourceLocation = #_sourceLocation
) {
    let actual = bits(set, expected.count)
    #expect(actual == expected, sourceLocation: sourceLocation)
}

private func changeRanges(
    _ changes1: DiffBitSet,
    _ changes2: DiffBitSet,
    count1: Int,
    count2: Int
) -> [DiffRange] {
    var ranges: [DiffRange] = []
    var x = 0
    var y = 0
    while x < count1 || y < count2 {
        while x < count1 && y < count2 && !changes1[x] && !changes2[y] {
            x += 1
            y += 1
        }
        let startX = x
        let startY = y
        while x < count1 && changes1[x] { x += 1 }
        while y < count2 && changes2[y] { y += 1 }
        if x == startX && y == startY { break }
        ranges.append(DiffRange(startX, x, startY, y))
    }
    return ranges
}

private func change(line0: Int, line1: Int, inserted: Int, deleted: Int) -> DiffRange {
    DiffRange(line0, line0 + deleted, line1, line1 + inserted)
}

@discardableResult
private func verifyLCS(
    _ first: [Int],
    _ second: [Int],
    start1: Int,
    count1: Int,
    start2: Int,
    count2: Int,
    changes1: DiffBitSet,
    changes2: DiffBitSet,
    sourceLocation: SourceLocation = #_sourceLocation
) -> Int {
    let unchanged1 = (start1..<(start1 + count1)).filter { !changes1[$0] }
    let unchanged2 = (start2..<(start2 + count2)).filter { !changes2[$0] }
    #expect(unchanged1.count == unchanged2.count, sourceLocation: sourceLocation)
    for (index1, index2) in zip(unchanged1, unchanged2) {
        #expect(first[index1] == second[index2], sourceLocation: sourceLocation)
    }
    let markedOutside1 = (0..<first.count).filter { ($0 < start1 || $0 >= start1 + count1) && changes1[$0] }
    let markedOutside2 = (0..<second.count).filter { ($0 < start2 || $0 >= start2 + count2) && changes2[$0] }
    #expect(markedOutside1.isEmpty, sourceLocation: sourceLocation)
    #expect(markedOutside2.isEmpty, sourceLocation: sourceLocation)
    return min(unchanged1.count, unchanged2.count)
}

@discardableResult
private func verifyWhole(
    _ first: [Int],
    _ second: [Int],
    _ changes1: DiffBitSet,
    _ changes2: DiffBitSet,
    sourceLocation: SourceLocation = #_sourceLocation
) -> Int {
    verifyLCS(
        first,
        second,
        start1: 0,
        count1: first.count,
        start2: 0,
        count2: second.count,
        changes1: changes1,
        changes2: changes2,
        sourceLocation: sourceLocation
    )
}

private func verifyCompare<T: Hashable>(
    _ changes: DiffChanges,
    _ first: [T],
    _ second: [T],
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(changes.length1 == first.count, sourceLocation: sourceLocation)
    #expect(changes.length2 == second.count, sourceLocation: sourceLocation)

    var cursor1 = 0
    var cursor2 = 0
    var unchangedLength = 0
    var previousWasUnchanged: Bool?
    for item in changes.iterateAll() {
        #expect(item.range.start1 == cursor1, sourceLocation: sourceLocation)
        #expect(item.range.start2 == cursor2, sourceLocation: sourceLocation)
        #expect(!item.range.isEmpty, sourceLocation: sourceLocation)
        #expect(previousWasUnchanged != item.isUnchanged, sourceLocation: sourceLocation)
        if item.isUnchanged {
            #expect(item.range.length1 == item.range.length2, sourceLocation: sourceLocation)
            if item.range.length1 == item.range.length2 {
                for offset in 0..<item.range.length1 {
                    #expect(
                        first[item.range.start1 + offset] == second[item.range.start2 + offset],
                        sourceLocation: sourceLocation
                    )
                }
            }
            unchangedLength += item.range.length1
        }
        previousWasUnchanged = item.isUnchanged
        cursor1 = item.range.end1
        cursor2 = item.range.end2
    }
    #expect(cursor1 == first.count, sourceLocation: sourceLocation)
    #expect(cursor2 == second.count, sourceLocation: sourceLocation)
    #expect(unchangedLength == bruteForceLCSLength(first, second), sourceLocation: sourceLocation)
}

private func uniqueMatching(_ first: [Int], _ second: [Int]) -> (first: [Int], second: [Int])? {
    UniqueLCS(
        first: first,
        second: second,
        start1: 0,
        count1: first.count,
        start2: 0,
        count2: second.count
    ).execute()
}

private func myersChanges(_ first: [Int], _ second: [Int]) throws -> (DiffBitSet, DiffBitSet) {
    var lcs = MyersLCS(first: first, second: second)
    try lcs.execute()
    return (lcs.changes1, lcs.changes2)
}

private func patienceChanges(_ first: [Int], _ second: [Int]) throws -> (DiffBitSet, DiffBitSet) {
    var lcs = PatienceIntLCS(first: first, second: second)
    try lcs.execute()
    return (lcs.changes1, lcs.changes2)
}

private func patienceAborts(_ first: [Int], _ second: [Int]) -> Bool {
    var lcs = PatienceIntLCS(first: first, second: second)
    do {
        try lcs.execute(failOnSmallReduction: true)
        return false
    } catch is DiffTooBigError {
        return true
    } catch {
        Issue.record("unexpected error: \(error)")
        return false
    }
}

@Suite
struct UniqueLCSTests {
    @Test(arguments: [
        SequencePair([1, 2, 3], [4, 5, 6]),
        SequencePair([1, 2, 1], [1, 3, 1]),
        SequencePair([1, 2, 3, 3, 2, 1], [1, 2, 3]),
        SequencePair([1, 2, 3], [1, 2, 3, 3, 2, 1]),
        SequencePair([1, 2, 1], [2, 1, 2]),
        SequencePair([], [2, 1, 2]),
        SequencePair([1, 2, 2], []),
        SequencePair([], [])
    ])
    func noElementUniqueOnBothSidesYieldsNoMatching(pair: SequencePair) {
        #expect(uniqueMatching(pair.first, pair.second) == nil)
    }

    @Test
    func singleUniqueElementIsMatchedWhateverSurroundsIt() throws {
        let cases: [(SequencePair, [Int], [Int])] = [
            (SequencePair([1], [1]), [0], [0]),
            (SequencePair([5, 1], [1]), [1], [0]),
            (SequencePair([1], [2, 1]), [0], [1]),
            (SequencePair([1], [1, 4]), [0], [0]),
            (SequencePair([1, 3], [1]), [0], [0]),
            (SequencePair([5, 1, 3], [2, 1, 4]), [1], [1])
        ]
        for (pair, expected1, expected2) in cases {
            let matching = try #require(uniqueMatching(pair.first, pair.second), "\(pair.testDescription)")
            #expect(matching.first == expected1, "\(pair.testDescription)")
            #expect(matching.second == expected2, "\(pair.testDescription)")
        }
    }

    @Test
    func repeatedElementsAreSkippedAndUniqueOnesFormTheChain() throws {
        let matching = try #require(uniqueMatching(
            [2, 4, 6, 1, 8, 3, 8, 2, 6, 5, 2, 4, 7, 11, 13],
            [1, 10, 2, 3, 5, 7, 11, 13, 12]
        ))

        #expect(matching.first == [3, 5, 9, 12, 13, 14])
        #expect(matching.second == [0, 3, 4, 5, 6, 7])
    }

    @Test
    func elementRepeatedOnlyInSecondSequenceIsDropped() throws {
        let matching = try #require(uniqueMatching([1, 2, 3], [2, 2, 1, 3]))

        #expect(matching.first == [0, 2])
        #expect(matching.second == [2, 3])
    }

    @Test
    func elementRepeatedThreeTimesInSecondSequenceStaysDropped() throws {
        let matching = try #require(uniqueMatching([1, 2, 3], [2, 2, 2, 1, 3]))

        #expect(matching.first == [0, 2])
        #expect(matching.second == [3, 4])
    }

    @Test
    func resultIsRelativeToTheSubrange() throws {
        let first = [9, 9, 1, 2, 3, 9]
        let second = [7, 1, 2, 3, 7]
        let matching = try #require(UniqueLCS(
            first: first,
            second: second,
            start1: 2,
            count1: 3,
            start2: 1,
            count2: 3
        ).execute())

        #expect(matching.first == [0, 1, 2])
        #expect(matching.second == [0, 1, 2])
    }

    @Test
    func elementsOutsideTheSubrangeAreIgnored() {
        let first = [1, 2, 3, 4]
        let second = [4, 3, 2, 5]
        let matching = UniqueLCS(first: first, second: second, start1: 0, count1: 2, start2: 2, count2: 2).execute()

        #expect(matching?.first == [1])
        #expect(matching?.second == [0])
    }

    @Test(arguments: [
        ([1, 2, 3], [1, 2, 3]),
        ([5, 6, 1, 2, 3], [1, 2, 3]),
        ([0, 8, 4, 12, 2, 10, 6, 14, 1, 9, 5, 13, 3, 7, 15], [0, 2, 6, 9, 13, 15]),
        ([1, 9, 3, 8, 11, 4, 5, 6, 19, 7], [1, 3, 4, 5, 6, 7])
    ] as [([Int], [Int])])
    func resultIsTheLongestIncreasingSubsequence(sequence: [Int], expected: [Int]) throws {
        let maximum = (sequence.max() ?? 0) + 1
        var second = [Int](repeating: 0, count: maximum + 2)
        var first: [Int] = []
        for (index, value) in sequence.enumerated() {
            #expect(second[value] == 0)
            first.append(index + 1)
            second[value] = index + 1
        }

        let result = try #require(uniqueMatching(first, second))

        #expect(result.first.count == result.second.count)
        #expect(result.first.map { sequence[$0] } == expected)
    }

    @Test
    func randomSequencesMatchTheLongestCommonSubsequenceOfElementsUniqueOnBothSides() {
        var generator = SplitMix64(seed: 0x5EED_0001)
        for _ in 0..<500 {
            let alphabet = Int.random(in: 2...12, using: &generator)
            let first = randomSequence(length: Int.random(in: 0...20, using: &generator), alphabet: alphabet, using: &generator)
            let second = randomSequence(length: Int.random(in: 0...20, using: &generator), alphabet: alphabet, using: &generator)
            let uniqueInFirst = Set(Dictionary(grouping: first, by: { $0 }).filter { $0.value.count == 1 }.keys)
            let uniqueInSecond = Set(Dictionary(grouping: second, by: { $0 }).filter { $0.value.count == 1 }.keys)
            let shared = uniqueInFirst.intersection(uniqueInSecond)
            let filtered1 = first.filter { shared.contains($0) }
            let filtered2 = second.filter { shared.contains($0) }

            guard let matching = uniqueMatching(first, second) else {
                #expect(shared.isEmpty, "\(first) vs \(second)")
                continue
            }
            #expect(matching.first.count == bruteForceLCSLength(filtered1, filtered2), "\(first) vs \(second)")
            #expect(matching.first == matching.first.sorted(), "\(first) vs \(second)")
            #expect(matching.second == matching.second.sorted(), "\(first) vs \(second)")
            for (index1, index2) in zip(matching.first, matching.second) {
                #expect(first[index1] == second[index2], "\(first) vs \(second)")
                #expect(shared.contains(first[index1]), "\(first) vs \(second)")
            }
        }
    }
}

@Suite
struct MyersLCSTests {
    @Test
    func equalSequencesHaveNoChanges() throws {
        let (changes1, changes2) = try myersChanges([1, 2, 3], [1, 2, 3])

        #expect(markedCount(changes1, 3) + markedCount(changes2, 3) == 0)
        #expect(changeRanges(changes1, changes2, count1: 3, count2: 3).isEmpty)
    }

    @Test
    func singleChangeAtTheEndOfTheSequences() throws {
        let (changes1, changes2) = try myersChanges([1, 2], [1, 3])

        #expect(markedCount(changes1, 2) + markedCount(changes2, 2) == 2)
        #expect(changeRanges(changes1, changes2, count1: 2, count2: 2) == [change(line0: 1, line1: 1, inserted: 1, deleted: 1)])
    }

    @Test
    func singleChangeAtTheBeginningOfTheSequences() throws {
        let (changes1, changes2) = try myersChanges([1, 3], [2, 3])

        #expect(markedCount(changes1, 2) + markedCount(changes2, 2) == 2)
        #expect(changeRanges(changes1, changes2, count1: 2, count2: 2) == [change(line0: 0, line1: 0, inserted: 1, deleted: 1)])
    }

    @Test
    func extraElementAtTheEndOfTheSecondSequence() throws {
        let (changes1, changes2) = try myersChanges([1, 2], [1, 2, 3])

        #expect(markedCount(changes1, 2) + markedCount(changes2, 3) == 1)
        #expect(changeRanges(changes1, changes2, count1: 2, count2: 3) == [change(line0: 2, line1: 2, inserted: 1, deleted: 0)])
    }

    @Test
    func extraElementAtTheBeginningOfTheFirstSequence() throws {
        let (changes1, changes2) = try myersChanges([1, 2, 3], [2, 3])

        #expect(markedCount(changes1, 3) + markedCount(changes2, 2) == 1)
        #expect(changeRanges(changes1, changes2, count1: 3, count2: 2) == [change(line0: 0, line1: 0, inserted: 0, deleted: 1)])
    }

    @Test
    func singleMiddleElementIsKept() throws {
        let (changes1, changes2) = try myersChanges([1, 2, 3], [4, 2, 5])

        #expect(markedCount(changes1, 3) + markedCount(changes2, 3) == 4)
        #expect(
            changeRanges(changes1, changes2, count1: 3, count2: 3) == [
                change(line0: 0, line1: 0, inserted: 1, deleted: 1),
                change(line0: 2, line1: 2, inserted: 1, deleted: 1)
            ]
        )
    }

    @Test
    func absolutelyDifferentSequencesMarkEverything() throws {
        let (small1, small2) = try myersChanges([1, 2], [3, 4])
        let (large1, large2) = try myersChanges([1, 2, 3], [4, 5, 6])

        #expect(markedCount(small1, 2) + markedCount(small2, 2) == 4)
        #expect(markedCount(large1, 3) + markedCount(large2, 3) == 6)
        expectBits(small1, [1, 1])
        expectBits(small2, [1, 1])
        expectBits(large1, [1, 1, 1])
        expectBits(large2, [1, 1, 1])
    }

    @Test
    func equalRunsAreKeptWhenOnlyTheUniqueElementMoves() throws {
        let (changes1, changes2) = try myersChanges([1, 1, 2, 2, 10], [10, 1, 1, 2, 2])

        expectBits(changes1, [0, 0, 0, 0, 1])
        expectBits(changes2, [1, 0, 0, 0, 0])
    }

    @Test
    func movedFunctionBodyKeepsTheLongerSharedRuns() throws {
        let first = [1, 2, 3, 4, 5, 6, 7, 8, 7, 9, 10, 2, 11, 12, 5, 13, 7, 8, 7]
        let second = [10, 2, 11, 12, 5, 13, 7, 8, 7, 9, 1, 2, 3, 4, 5, 6, 7, 8, 7]
        let (changes1, changes2) = try myersChanges(first, second)

        expectBits(changes1, [1, 0, 1, 1, 0, 1, 0, 0, 0, 0, 1, 0, 1, 1, 0, 1])
        expectBits(changes2, [1, 0, 1, 1, 0, 1, 0, 0, 0, 0, 1, 0, 1, 1, 0, 1])
        verifyWhole(first, second, changes1, changes2)
    }

    @Test
    func emptySideMarksNothingBecauseTheSubrangeIsEmpty() throws {
        let (changes1, changes2) = try myersChanges([1, 2, 3], [])

        #expect(markedCount(changes1, 3) == 3)
        #expect(markedCount(changes2, 0) == 0)
    }

    @Test(arguments: [2, 3, 5, 20])
    func everyExecutionModeFindsTheLongestCommonSubsequenceOfRandomSubranges(alphabet: Int) throws {
        var generator = SplitMix64(seed: 0xA17E_0000 &+ UInt64(alphabet))
        for _ in 0..<250 {
            let first = randomSequence(length: Int.random(in: 1...60, using: &generator), alphabet: alphabet, using: &generator)
            let second = randomSequence(length: Int.random(in: 1...60, using: &generator), alphabet: alphabet, using: &generator)
            let start1 = Int.random(in: 0..<first.count, using: &generator)
            let start2 = Int.random(in: 0..<second.count, using: &generator)
            let count1 = Int.random(in: 0..<(first.count - start1), using: &generator)
            let count2 = Int.random(in: 0..<(second.count - start2), using: &generator)
            let expected = bruteForceLCSLength(
                Array(first[start1..<(start1 + count1)]),
                Array(second[start2..<(start2 + count2)])
            )

            for mode in 0..<3 {
                var lcs = MyersLCS(
                    first: first,
                    second: second,
                    start1: start1,
                    count1: count1,
                    start2: start2,
                    count2: count2,
                    changes1: DiffBitSet(count: first.count),
                    changes2: DiffBitSet(count: second.count)
                )
                switch mode {
                case 0: try lcs.execute()
                case 1: try lcs.executeLinear()
                default: try lcs.executeWithThreshold()
                }
                let actual = verifyLCS(
                    first,
                    second,
                    start1: start1,
                    count1: count1,
                    start2: start2,
                    count2: count2,
                    changes1: lcs.changes1,
                    changes2: lcs.changes2
                )
                #expect(actual == expected, "mode \(mode): \(first) vs \(second) [\(start1),\(count1)] [\(start2),\(count2)]")
            }
        }
    }
}

@Suite
struct PatienceIntLCSTests {
    @Test
    func equalSequencesHaveNoChanges() throws {
        let (changes1, changes2) = try patienceChanges([1, 2, 3], [1, 2, 3])

        expectBits(changes1, [0, 0, 0])
        expectBits(changes2, [0, 0, 0])
    }

    @Test
    func changeAtTheEnd() throws {
        let (changes1, changes2) = try patienceChanges([1, 2], [1, 3])

        expectBits(changes1, [0, 1])
        expectBits(changes2, [0, 1])
    }

    @Test
    func changeAtTheBeginning() throws {
        let (changes1, changes2) = try patienceChanges([1, 3], [2, 3])

        expectBits(changes1, [1, 0])
        expectBits(changes2, [1, 0])
    }

    @Test
    func insertionAtTheEnd() throws {
        let (changes1, changes2) = try patienceChanges([1, 2], [1, 2, 3])

        expectBits(changes1, [0, 0])
        expectBits(changes2, [0, 0, 1])
    }

    @Test
    func deletionAtTheBeginning() throws {
        let (changes1, changes2) = try patienceChanges([1, 2, 3], [2, 3])

        expectBits(changes1, [1, 0, 0])
        expectBits(changes2, [0, 0])
    }

    @Test
    func singleMiddleElementIsKept() throws {
        let (changes1, changes2) = try patienceChanges([1, 2, 3], [4, 2, 5])

        expectBits(changes1, [1, 0, 1])
        expectBits(changes2, [1, 0, 1])
    }

    @Test
    func absolutelyDifferentSequencesMarkEverything() throws {
        let (small1, small2) = try patienceChanges([1, 2], [3, 4])
        let (large1, large2) = try patienceChanges([1, 2, 3], [4, 5, 6])

        expectBits(small1, [1, 1])
        expectBits(small2, [1, 1])
        expectBits(large1, [1, 1, 1])
        expectBits(large2, [1, 1, 1])
    }

    @Test
    func movedUniqueElementBreaksTheRunsAroundIt() throws {
        let (changes1, changes2) = try patienceChanges([1, 1, 2, 2, 10], [10, 1, 1, 2, 2])

        expectBits(changes1, [1, 1, 1, 1, 0])
        expectBits(changes2, [0, 1, 1, 1, 1])
    }

    @Test
    func movedFunctionAnchorsOnTheLongestUniqueChain() throws {
        let (changes1, changes2) = try patienceChanges(
            [1, 2, 3, 4, 5, 6, 7, 8, 7, 9, 10, 2, 11, 12, 5, 13, 7, 8, 7],
            [10, 2, 11, 12, 5, 13, 7, 8, 7, 9, 1, 2, 3, 4, 5, 6, 7, 8, 7]
        )

        expectBits(changes1, [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0])
        expectBits(changes2, [0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1])
    }

    @Test
    func regressionWithTwoMovedElements() throws {
        let (changes1, changes2) = try patienceChanges(
            [2, 3, 4, 6, 7, 8, 9, 11, 12, 4, 6, 11, 15],
            [2, 3, 6, 7, 8, 9, 6, 11, 12, 4, 11, 15, 6]
        )

        expectBits(changes1, [0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0])
        expectBits(changes2, [0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0])
    }

    @Test
    func innerChunksBetweenRepeatedSeparatorsAreDiffedSeparately() throws {
        let cases: [(SequencePair, [Int], [Int])] = [
            (
                SequencePair([0, 2, 0, 3, 0, 4, 0, 5, 0, 6, 0, 7, 0], [1, 2, 1, 3, 1, 4, 1, 5, 1, 6, 1, 7, 1]),
                [1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1],
                [1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1]
            ),
            (
                SequencePair([0, 2, 3, 0, 4, 5, 0], [1, 2, 1, 3, 4, 5, 1]),
                [1, 0, 0, 1, 0, 0, 1],
                [1, 0, 1, 0, 0, 0, 1]
            ),
            (
                SequencePair([15, 1, 2, 3, 1, 4, 5, 1, 15], [13, 1, 2, 1, 3, 4, 5, 1, 13]),
                [1, 0, 0, 0, 1, 0, 0, 0, 1],
                [1, 0, 0, 1, 0, 0, 0, 0, 1]
            ),
            (
                SequencePair([15, 0, 2, 0, 3, 0, 4, 0, 5, 0, 6, 0, 7, 0, 15], [13, 0, 2, 0, 3, 0, 4, 0, 5, 0, 6, 0, 7, 0, 13]),
                [1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1],
                [1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1]
            )
        ]
        for (pair, expected1, expected2) in cases {
            let (changes1, changes2) = try patienceChanges(pair.first, pair.second)
            expectBits(changes1, expected1)
            expectBits(changes2, expected2)
        }
    }

    @Test
    func emptySidesMarkTheOtherSideEntirely() throws {
        let (onlyFirst1, onlyFirst2) = try patienceChanges([1, 2, 3], [])
        let (onlySecond1, onlySecond2) = try patienceChanges([], [4, 5])
        let (neither1, neither2) = try patienceChanges([], [])

        expectBits(onlyFirst1, [1, 1, 1])
        #expect(markedCount(onlyFirst2, 0) == 0)
        #expect(markedCount(onlySecond1, 0) == 0)
        expectBits(onlySecond2, [1, 1])
        #expect(markedCount(neither1, 0) + markedCount(neither2, 0) == 0)
    }

    @Test(arguments: [
        SequencePair([1, 2, 3], [1, 2, 3]),
        SequencePair([100, 1, 2, 3, 4, 5, 100], [1, 2, 3, 4]),
        SequencePair(
            [100, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 100],
            [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0]
        ),
        SequencePair(
            [100, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 200, 1, 0, 100],
            [2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 2]
        )
    ])
    func reducibleInputsDoNotAbortWhenFailingOnSmallReduction(pair: SequencePair) {
        #expect(!patienceAborts(pair.first, pair.second))
    }

    @Test(arguments: [
        SequencePair([4, 1, 2, 3], [500, 100, 600]),
        SequencePair([4, 1, 2, 3, 100], [5, 1, 6, 8, 9, 10]),
        SequencePair(
            [100, 3, 2, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 200, 1, 0, 100],
            [2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 1, 0, 2]
        )
    ])
    func barelyReducibleInputsAbortWhenFailingOnSmallReduction(pair: SequencePair) {
        #expect(patienceAborts(pair.first, pair.second))
    }

    @Test
    func randomSequencesYieldValidCommonSubsequencesNeverLongerThanTheOptimum() throws {
        var generator = SplitMix64(seed: 0x9A71_E0CE)
        for alphabet in [2, 5, 30, 80] {
            for _ in 0..<200 {
                let first = randomSequence(length: Int.random(in: 0...60, using: &generator), alphabet: alphabet, using: &generator)
                let second = randomSequence(length: Int.random(in: 0...60, using: &generator), alphabet: alphabet, using: &generator)

                let (changes1, changes2) = try patienceChanges(first, second)
                let kept = verifyWhole(first, second, changes1, changes2)

                #expect(kept <= bruteForceLCSLength(first, second), "\(first) vs \(second)")
            }
        }
    }

    @Test
    func failingOnSmallReductionEitherAbortsOrStillYieldsAValidResult() {
        var generator = SplitMix64(seed: 0x0AB0_47ED)
        for alphabet in [2, 5, 30] {
            for _ in 0..<200 {
                let first = randomSequence(length: Int.random(in: 0...60, using: &generator), alphabet: alphabet, using: &generator)
                let second = randomSequence(length: Int.random(in: 0...60, using: &generator), alphabet: alphabet, using: &generator)
                var lcs = PatienceIntLCS(first: first, second: second)
                do {
                    try lcs.execute(failOnSmallReduction: true)
                    verifyWhole(first, second, lcs.changes1, lcs.changes2)
                } catch is DiffTooBigError {
                    continue
                } catch {
                    Issue.record("unexpected error: \(error)")
                }
            }
        }
    }

    @Test
    func permutationsAreMatchedOptimally() throws {
        var generator = SplitMix64(seed: 0x9E57_0001)
        for _ in 0..<200 {
            let size = Int.random(in: 1...40, using: &generator)
            let first = Array(0..<size).shuffled(using: &generator)
            let second = Array(0..<size).shuffled(using: &generator)

            let (changes1, changes2) = try patienceChanges(first, second)
            let kept = verifyWhole(first, second, changes1, changes2)

            #expect(kept == bruteForceLCSLength(first, second), "\(first) vs \(second)")
        }
    }
}

@Suite
struct ReindexerTests {
    @Test
    func nothingIsDiscardedWhenEveryElementOccursOnBothSides() {
        var reindexer = Reindexer()
        let discarded = reindexer.discardUnique([1, 2, 3], [3, 2, 1, 2, 2])

        #expect(discarded.first == [1, 2, 3])
        #expect(discarded.second == [3, 2, 1, 2, 2])
    }

    @Test
    func elementsAbsentFromTheOtherSideAreDiscarded() {
        var reindexer = Reindexer()
        let discarded = reindexer.discardUnique([1, 2, 3], [3, 4, 1, 3])

        #expect(discarded.first == [1, 3])
        #expect(discarded.second == [3, 1, 3])
    }

    @Test
    func disjointSequencesDiscardEverything() {
        var reindexer = Reindexer()
        let discarded = reindexer.discardUnique([1, 2, 3], [4, 5])

        #expect(discarded.first.isEmpty)
        #expect(discarded.second.isEmpty)
    }

    @Test
    func discardingIsDeterminedBySecondSequenceFirstThenFirstAgainstTheReducedOne() {
        var reindexer = Reindexer()
        let discarded = reindexer.discardUnique([1, 2, 3, 7], [3, 7, 9, 2, 8])

        #expect(discarded.first == [2, 3, 7])
        #expect(discarded.second == [3, 7, 2])
    }

    @Test
    func reindexRestoresOriginalPositionsOfTheDiscardedMatching() throws {
        var reindexer = Reindexer()
        let discarded = reindexer.discardUnique([1, 2, 3], [3, 4, 1, 3])
        let (changes1, changes2) = try myersChanges(discarded.first, discarded.second)
        var builder = LCSBuilder(startShift: 0)

        reindexer.reindex((changes1, changes2), into: &builder)

        #expect(builder.ranges == [DiffRange(0, 0, 0, 2), DiffRange(1, 2, 3, 3)])
    }

    @Test
    func reindexOfDisjointSequencesIsOneChangeCoveringBoth() {
        var reindexer = Reindexer()
        let discarded = reindexer.discardUnique([1, 2, 3], [4, 5])
        var builder = LCSBuilder(startShift: 0)

        reindexer.reindex((DiffBitSet(), DiffBitSet()), into: &builder)

        #expect(discarded.first.isEmpty)
        #expect(builder.ranges == [DiffRange(0, 3, 0, 2)])
    }

    @Test
    func reindexWhenNothingIsDiscardedUsesTheChangesDirectly() throws {
        var reindexer = Reindexer()
        let discarded = reindexer.discardUnique([1, 2, 1], [2, 1, 2])
        let (changes1, changes2) = try myersChanges(discarded.first, discarded.second)
        var builder = LCSBuilder(startShift: 10)

        reindexer.reindex((changes1, changes2), into: &builder)

        #expect(builder.ranges == [DiffRange(10, 11, 10, 10), DiffRange(13, 13, 12, 13)])
    }

    @Test
    func builderAccumulatesEqualRunsAndChangesFromTheStartShift() {
        var builder = LCSBuilder(startShift: 5)

        builder.addEqual(2)
        builder.addChange(1, 3)
        builder.addEqual(4)
        builder.addChange(0, 2)

        #expect(builder.ranges == [DiffRange(7, 8, 7, 10), DiffRange(12, 12, 14, 16)])
        #expect(builder.index1 == 12)
        #expect(builder.index2 == 16)
    }

    @Test(arguments: [
        SequencePair([1, 2, 3], [4, 5]),
        SequencePair([], [4, 5]),
        SequencePair([1, 2, 3], []),
        SequencePair([13, 15, 1, 2, 3], [17, 1, 3]),
        SequencePair([1, 2, 3, 13, 15], [1, 3, 17]),
        SequencePair([1, 1, 2, 2, 10], [10, 1, 1, 2, 2]),
        SequencePair(
            [1, 2, 3, 4, 5, 6, 7, 8, 7, 9, 10, 2, 11, 12, 5, 13, 7, 8, 7],
            [10, 2, 11, 12, 5, 13, 7, 8, 7, 9, 1, 2, 3, 4, 5, 6, 7, 8, 7]
        ),
        SequencePair([0, 2, 0, 3, 0, 4, 0, 5, 0, 6, 0, 7, 0], [1, 2, 1, 3, 1, 4, 1, 5, 1, 6, 1, 7, 1]),
        SequencePair([0, 2, 3, 0, 4, 5, 0], [1, 2, 1, 3, 4, 5, 1]),
        SequencePair([15, 1, 2, 3, 1, 4, 5, 1, 15], [13, 1, 2, 1, 3, 4, 5, 1, 13]),
        SequencePair([15, 0, 2, 0, 3, 0, 4, 0, 5, 0, 6, 0, 7, 0, 15], [13, 0, 2, 0, 3, 0, 4, 0, 5, 0, 6, 0, 7, 0, 13])
    ])
    func discardThenDiffThenReindexKeepsAnOptimalCommonSubsequence(pair: SequencePair) throws {
        try checkReindexRoundTrip(pair.first, pair.second)
    }

    @Test
    func randomSequencesRoundTripThroughDiscardAndReindex() throws {
        var generator = SplitMix64(seed: 0x4E1D_0001)
        for _ in 0..<400 {
            let alphabet = Int.random(in: 2...60, using: &generator)
            let first = randomSequence(length: Int.random(in: 0...50, using: &generator), alphabet: alphabet, using: &generator)
            let second = randomSequence(length: Int.random(in: 0...50, using: &generator), alphabet: alphabet, using: &generator)

            try checkReindexRoundTrip(first, second)
        }
    }

    @Test
    func hundredElementRandomExamplesRoundTripThroughDiscardAndReindex() throws {
        var generator = SplitMix64(seed: 0x4E1D_0002)
        for _ in 0..<10 {
            let first = randomSequence(length: 100, alphabet: 60, using: &generator)
            let second = randomSequence(length: 100, alphabet: 60, using: &generator)

            try checkReindexRoundTrip(first, second)
        }
    }

    private func checkReindexRoundTrip(
        _ first: [Int],
        _ second: [Int],
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        var reindexer = Reindexer()
        let discarded = reindexer.discardUnique(first, second)
        let (changes1, changes2) = try myersChanges(discarded.first, discarded.second)
        var builder = LCSBuilder(startShift: 0)

        reindexer.reindex((changes1, changes2), into: &builder)

        var marked1 = DiffBitSet(count: first.count)
        var marked2 = DiffBitSet(count: second.count)
        for range in builder.ranges {
            marked1.set(from: range.start1, to: range.end1)
            marked2.set(from: range.start2, to: range.end2)
        }
        let kept = verifyWhole(first, second, marked1, marked2, sourceLocation: sourceLocation)
        #expect(kept == bruteForceLCSLength(first, second), "\(first) vs \(second)", sourceLocation: sourceLocation)
    }
}

@Suite
struct SequenceDiffAlgorithmTests {
    private static let data123 = ["1", "2", "3"]
    private static let dataAB = ["a", "b"]
    private static let data12AB23 = ["1", "2", "a", "b", "2", "3"]
    private static let data123Padded = ["x", "y", "z", "1", "2", "3", "alpha", "beta"]
    private static let data12AB23Padded = ["x", "y", "z", "1", "2", "a", "b", "2", "3", "alpha", "beta"]

    @Test
    func equalSequencesProduceNoChange() throws {
        let changes = try SequenceDiff.compare(Self.data123, Self.data123)

        #expect(changes.changes.isEmpty)
        #expect(changes.isEmpty)
    }

    @Test
    func completelyDifferentSequencesAreOneChange() throws {
        let changes = try SequenceDiff.compare(Self.dataAB, Self.data123)

        #expect(changes.changes == [change(line0: 0, line1: 0, inserted: 3, deleted: 2)])
    }

    @Test
    func sameMiddleElementSplitsTheChange() throws {
        let changes = try SequenceDiff.compare(Self.data123, ["a", "2", "b"])

        #expect(
            changes.changes == [
                change(line0: 0, line1: 0, inserted: 1, deleted: 1),
                change(line0: 2, line1: 2, inserted: 1, deleted: 1)
            ]
        )
    }

    @Test
    func overlappingInsertionIsReportedAsPureInsertion() throws {
        let changes = try SequenceDiff.compare(Self.data123, Self.data12AB23)

        #expect(changes.changes == [change(line0: 2, line1: 2, inserted: 3, deleted: 0)])
    }

    @Test
    func commonPrefixAndSuffixAreTrimmedBeforeComparison() throws {
        let changes = try SequenceDiff.compare(Self.data123Padded, Self.data12AB23Padded)

        #expect(changes.changes == [change(line0: 5, line1: 5, inserted: 3, deleted: 0)])
    }

    @Test
    func sequenceEqualUpToOneEndReportsTheTail() throws {
        let changes = try SequenceDiff.compare(Self.dataAB, ["a", "b", "1"])

        #expect(changes.changes == [change(line0: 2, line1: 2, inserted: 1, deleted: 0)])
    }

    @Test
    func emptySequencesAgainstSomething() throws {
        let empty: [String] = []

        #expect(try SequenceDiff.compare(empty, empty).changes.isEmpty)
        #expect(try SequenceDiff.compare(Self.dataAB, empty).changes == [change(line0: 0, line1: 0, inserted: 0, deleted: 2)])
        #expect(try SequenceDiff.compare(empty, Self.data123).changes == [change(line0: 0, line1: 0, inserted: 3, deleted: 0)])
    }

    @Test
    func missingValuesParticipateLikeAnyOtherElement() throws {
        let first: [String?] = ["1", "2", nil, "a", "b", nil, "2", "3"]
        let second: [String?] = [nil, "1", "2", "a", "b", "2", "3"]

        let changes = try SequenceDiff.compare(first, second)

        #expect(
            changes.changes == [
                change(line0: 0, line1: 0, inserted: 1, deleted: 0),
                change(line0: 2, line1: 3, inserted: 0, deleted: 1),
                change(line0: 5, line1: 5, inserted: 0, deleted: 1)
            ]
        )
    }

    @Test
    func sequencesWithoutCommonElementsAreOneChangeAfterTrimming() throws {
        let changes = try SequenceDiff.compare([0, 1, 2, 9], [0, 5, 6, 7, 9])

        #expect(changes.changes == [DiffRange(1, 3, 1, 4)])
        #expect(changes.unchanged == [DiffRange(0, 1, 0, 1), DiffRange(3, 4, 4, 5)])
    }

    @Test
    func uniqueElementsOnOneSideAreDiscardedAndRestoredAtTheirOriginalPositions() throws {
        let first = [1, 2, 3, 4, 5]
        let second = [1, 9, 3, 8, 7, 5]

        let changes = try SequenceDiff.compare(first, second)

        #expect(changes.changes == [DiffRange(1, 2, 1, 2), DiffRange(3, 4, 3, 5)])
        verifyCompare(changes, first, second)
    }

    @Test
    func worksForAnyHashableElementType() throws {
        let characters = try SequenceDiff.compare(Array("kitten"), Array("sitting"))
        let words = try SequenceDiff.compare(["let", "x", "=", "1"], ["let", "y", "=", "1", ";"])

        verifyCompare(characters, Array("kitten"), Array("sitting"))
        #expect(words.changes == [DiffRange(1, 2, 1, 2), DiffRange(4, 4, 4, 5)])
    }

    @Test(arguments: [1, 2, 3, 4, 8, 20])
    func randomSequencesAreMinimalAndConsistent(alphabet: Int) throws {
        var generator = SplitMix64(seed: 0xD1FF_0000 &+ UInt64(alphabet))
        for _ in 0..<300 {
            let first = randomSequence(length: Int.random(in: 0...45, using: &generator), alphabet: alphabet, using: &generator)
            let second = randomSequence(length: Int.random(in: 0...45, using: &generator), alphabet: alphabet, using: &generator)

            verifyCompare(try SequenceDiff.compare(first, second), first, second)
        }
    }

    @Test
    func editedCopiesWithManyDistinctElementsAreMinimalAndConsistent() throws {
        var generator = SplitMix64(seed: 0xD1FF_1000)
        for _ in 0..<150 {
            let first = randomSequence(length: 50, alphabet: 1000, using: &generator)
            var second = first
            for _ in 0..<Int.random(in: 0...10, using: &generator) {
                let position = Int.random(in: 0...second.count, using: &generator)
                switch Int.random(in: 0..<3, using: &generator) {
                case 0 where position < second.count: second.remove(at: position)
                case 1 where position < second.count: second[position] = Int.random(in: 2000..<3000, using: &generator)
                default: second.insert(Int.random(in: 2000..<3000, using: &generator), at: position)
                }
            }

            verifyCompare(try SequenceDiff.compare(first, second), first, second)
        }
    }
}

@Suite
struct SequenceDiffLargeInputTests {
    private static let anchorCount = 10
    private static let gapLength = 120
    private static let reducedMyersLimit = 500

    @Test
    func uniqueAnchorsLetThePatienceFallbackSucceedWhenMyersExceedsItsBound() throws {
        var first: [Int] = []
        var second: [Int] = []
        var expected: [DiffRange] = []
        for index in 0..<Self.anchorCount {
            let start = index * (Self.gapLength + 1)
            first += [Int](repeating: 0, count: Self.gapLength) + [10 + index]
            second += [Int](repeating: 1, count: Self.gapLength) + [10 + index]
            expected.append(DiffRange(start, start + Self.gapLength, start, start + Self.gapLength))
        }
        first.append(1)
        second.append(0)
        let tail = Self.anchorCount * (Self.gapLength + 1)
        expected.append(DiffRange(tail, tail + 1, tail, tail + 1))

        let changes = try SequenceDiff.$myersLimit.withValue(Self.reducedMyersLimit) {
            try SequenceDiff.compare(first, second)
        }

        #expect(changes.changes == expected)
        #expect(changes.unchanged.count == Self.anchorCount)
        #expect(changes.unchanged.allSatisfy { $0.length1 == 1 && $0.start1 == $0.start2 })
    }

    @Test
    func inputsWithoutAnchorsThatExceedTheMyersBoundThrowDiffTooBig() {
        let half = 300
        let first = [Int](repeating: 0, count: half) + [Int](repeating: 1, count: half)
        let second = [Int](repeating: 1, count: half) + [Int](repeating: 0, count: half)

        #expect(throws: DiffTooBigError.self) {
            try SequenceDiff.$myersLimit.withValue(100) {
                try SequenceDiff.compare(first, second)
            }
        }
    }

    @Test
    func theDefaultMyersBoundAcceptsInputsThatFitIt() throws {
        let first = [Int](repeating: 0, count: 300) + [Int](repeating: 1, count: 300)
        let second = [Int](repeating: 1, count: 300) + [Int](repeating: 0, count: 300)

        let changes = try SequenceDiff.compare(first, second)

        verifyCompare(changes, first, second)
    }
}
