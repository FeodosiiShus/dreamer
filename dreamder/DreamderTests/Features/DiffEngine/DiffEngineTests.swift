import Foundation
import Testing
@testable import Dreamder

private struct SeededGenerator: RandomNumberGenerator {
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

private func lcsLength(_ first: [Int], _ second: [Int]) -> Int {
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

private func verify(
    _ changes: DiffChanges,
    _ first: [Int],
    _ second: [Int],
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
        #expect(item.range.start1 <= item.range.end1, sourceLocation: sourceLocation)
        #expect(item.range.start2 <= item.range.end2, sourceLocation: sourceLocation)
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
    #expect(unchangedLength == lcsLength(first, second), sourceLocation: sourceLocation)
}

@Suite
struct SequenceDiffTests {
    @Test
    func identicalSequencesHaveNoChanges() throws {
        let changes = try SequenceDiff.compare([1, 2, 3], [1, 2, 3])

        #expect(changes.changes.isEmpty)
        #expect(changes.unchanged == [DiffRange(0, 3, 0, 3)])
    }

    @Test
    func emptySequencesAreHandled() throws {
        #expect(try SequenceDiff.compare([Int](), [Int]()).changes.isEmpty)
        #expect(try SequenceDiff.compare([Int](), [1, 2]).changes == [DiffRange(0, 0, 0, 2)])
        #expect(try SequenceDiff.compare([1, 2], [Int]()).changes == [DiffRange(0, 2, 0, 0)])
    }

    @Test
    func insertionAndDeletionAtBothEnds() throws {
        #expect(try SequenceDiff.compare([2, 3], [1, 2, 3]).changes == [DiffRange(0, 0, 0, 1)])
        #expect(try SequenceDiff.compare([1, 2], [1, 2, 3]).changes == [DiffRange(2, 2, 2, 3)])
        #expect(try SequenceDiff.compare([1, 2, 3], [2, 3]).changes == [DiffRange(0, 1, 0, 0)])
        #expect(try SequenceDiff.compare([1, 2, 3], [1, 2]).changes == [DiffRange(2, 3, 2, 2)])
    }

    @Test
    func completelyDifferentSequencesAreOneChange() throws {
        let changes = try SequenceDiff.compare([1, 2, 3], [4, 5])

        #expect(changes.changes == [DiffRange(0, 3, 0, 2)])
        #expect(changes.unchanged.isEmpty)
    }

    @Test
    func middleReplacementKeepsCommonPrefixAndSuffix() throws {
        let changes = try SequenceDiff.compare([1, 2, 3, 4], [1, 9, 4])

        #expect(changes.changes == [DiffRange(1, 3, 1, 2)])
        #expect(changes.unchanged == [DiffRange(0, 1, 0, 1), DiffRange(3, 4, 2, 3)])
    }

    @Test
    func repeatedElementsDoNotBreakAlignment() throws {
        let first = [1, 1, 1, 2, 1, 1]
        let second = [1, 1, 2, 1, 1, 1]

        verify(try SequenceDiff.compare(first, second), first, second)
    }

    @Test
    func randomSequencesProduceMinimalConsistentScripts() throws {
        var generator = SeededGenerator(seed: 0xD1FF_E49E)
        for _ in 0..<300 {
            let alphabet = Int.random(in: 2...6, using: &generator)
            let firstLength = Int.random(in: 0...30, using: &generator)
            let secondLength = Int.random(in: 0...30, using: &generator)
            let first = (0..<firstLength).map { _ in Int.random(in: 0..<alphabet, using: &generator) }
            let second = (0..<secondLength).map { _ in Int.random(in: 0..<alphabet, using: &generator) }

            verify(try SequenceDiff.compare(first, second), first, second)
        }
    }

    @Test
    func randomSequencesWithManyUniqueElementsStayConsistent() throws {
        var generator = SeededGenerator(seed: 42)
        for _ in 0..<100 {
            let first = (0..<40).map { _ in Int.random(in: 0..<60, using: &generator) }
            var second = first
            for _ in 0..<Int.random(in: 0...8, using: &generator) {
                let position = Int.random(in: 0...second.count, using: &generator)
                if Bool.random(using: &generator) && position < second.count {
                    second.remove(at: position)
                } else {
                    second.insert(Int.random(in: 100..<200, using: &generator), at: position)
                }
            }

            verify(try SequenceDiff.compare(first, second), first, second)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func hundredThousandElementsWithSparseEditsAreFast() throws {
        let first = Array(0..<100_000)
        var second = first
        second.remove(at: 70_000)
        second.insert(-1, at: 30_000)
        second[50_000] = -2

        let changes = try SequenceDiff.compare(first, second)

        #expect(changes.changes.count == 3)
        #expect(changes.unchanged.reduce(0) { $0 + $1.length1 } == 100_000 - 2)
    }

    @Test
    func cancelledTaskThrowsCancellationError() async {
        let first = (0..<500).map { $0 % 7 }
        let second = (0..<500).map { ($0 * 3) % 7 }
        let task = Task { () async throws -> DiffChanges in
            while !Task.isCancelled { await Task.yield() }
            return try SequenceDiff.compare(first, second)
        }
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("expected CancellationError")
        } catch is CancellationError {
            return
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }
}

@Suite
struct LineRangeComparisonTests {
    private typealias Support = DiffEngineTestSupport

    private func ranges(_ left: [String], _ right: [String], _ policy: ComparisonPolicy) throws -> [DiffRange] {
        try ComparisonManager.compareLineRanges(left, right, policy: policy)
    }

    @Test(arguments: ComparisonPolicy.allCases)
    func identicalInputsHaveNoChanges(policy: ComparisonPolicy) throws {
        #expect(try ranges([], [], policy).isEmpty)
        #expect(try ranges(["a"], ["a"], policy).isEmpty)
        #expect(try ranges(["alpha beta", "", "gamma"], ["alpha beta", "", "gamma"], policy).isEmpty)
    }

    @Test(arguments: ComparisonPolicy.allCases)
    func emptySidesAreWholeInsertionsAndDeletions(policy: ComparisonPolicy) throws {
        #expect(try ranges([], ["a", "b"], policy) == [Support.ins(0, 0, 2)])
        #expect(try ranges(["a", "b"], [], policy) == [Support.del(0, 0, 2)])
    }

    @Test(arguments: ComparisonPolicy.allCases)
    func insertionAndDeletionAtTheStartAndEnd(policy: ComparisonPolicy) throws {
        #expect(try ranges(["b", "c"], ["a", "b", "c"], policy) == [Support.ins(0, 0, 1)])
        #expect(try ranges(["a", "b"], ["a", "b", "c"], policy) == [Support.ins(2, 2, 1)])
        #expect(try ranges(["a", "b", "c"], ["b", "c"], policy) == [Support.del(0, 0, 1)])
        #expect(try ranges(["a", "b", "c"], ["a", "b"], policy) == [Support.del(2, 2, 1)])
    }

    @Test
    func leadingAndTrailingWhitespaceUnderEachPolicy() throws {
        let left = ["a", " b ", "c"]
        let right = ["a", "b", "c"]

        #expect(try ranges(left, right, .default) == [Support.mod(1, 1, 1, 1)])
        #expect(try ranges(left, right, .trimWhitespaces).isEmpty)
        #expect(try ranges(left, right, .ignoreWhitespaces).isEmpty)
    }

    @Test
    func innerWhitespaceUnderEachPolicy() throws {
        let left = ["x  y"]
        let right = ["x y"]

        #expect(try ranges(left, right, .default) == [Support.mod(0, 0, 1, 1)])
        #expect(try ranges(left, right, .trimWhitespaces) == [Support.mod(0, 0, 1, 1)])
        #expect(try ranges(left, right, .ignoreWhitespaces).isEmpty)
    }

    @Test
    func whitespaceOnlyChangeOfOneLineDoesNotDisturbNeighbours() throws {
        let left = ["first line here", "second  line here", "third line here"]
        let right = ["first line here", "second line here", "third line here"]

        #expect(try ranges(left, right, .default) == [Support.mod(1, 1, 1, 1)])
        #expect(try ranges(left, right, .trimWhitespaces) == [Support.mod(1, 1, 1, 1)])
        #expect(try ranges(left, right, .ignoreWhitespaces).isEmpty)
    }

    @Test
    func contentChangeIsReportedUnderEveryPolicy() throws {
        let left = ["a", "b", "c"]
        let right = ["a", "B", "c"]

        for policy in ComparisonPolicy.allCases {
            #expect(try ranges(left, right, policy) == [Support.mod(1, 1, 1, 1)], "policy: \(policy)")
        }
    }

    @Test
    func importantLinesAnchorTheAlignment() throws {
        let left = ["{", "important statement one", "}", "{", "important statement two", "}"]
        let right = ["{", "important statement two", "}"]

        let changes = try ranges(left, right, .default)

        #expect(changes == [Support.del(0, 0, 3)])
    }

    @Test(.timeLimit(.minutes(1)))
    func tenThousandLinesWithSparseEdits() throws {
        let left = (0..<10_000).map { "line \($0) payload" }
        var right = left
        right[10] = "edited"
        right.insert("added", at: 5_000)
        right.remove(at: 9_000)

        let changes = try ranges(left, right, .default)

        try #require(changes.count == 3)
        #expect(changes[0] == Support.mod(10, 10, 1, 1))
        #expect(changes[1] == Support.ins(5_000, 5_000, 1))
        #expect(changes[2] == Support.del(8_999, 9_000, 1))
    }

    @Test(.timeLimit(.minutes(1)))
    func tenThousandLinesWithManyRepeatedLines() throws {
        let left = (0..<10_000).map { $0 % 3 == 0 ? "}" : "line \($0 % 50)" }
        var right = left
        right.insert("new block", at: 4_000)
        right.remove(at: 8_000)

        let changes = try ranges(left, right, .default)

        #expect(!changes.isEmpty)
        let result = DiffChanges(changes: changes, length1: left.count, length2: right.count)
        var unchangedLines = 0
        for range in result.unchanged {
            #expect(range.length1 == range.length2)
            for offset in 0..<range.length1 where left[range.start1 + offset] != right[range.start2 + offset] {
                Issue.record("unchanged range \(range) differs at offset \(offset)")
                return
            }
            unchangedLines += range.length1
        }
        #expect(unchangedLines >= left.count - 10)
    }

    @Test
    func cancelledTaskThrowsCancellationError() async {
        let left = (0..<500).map { "left line \($0) with several words" }
        let right = (0..<500).map { "right line \($0) with other words" }
        let task = Task { () async throws -> [DiffRange] in
            while !Task.isCancelled { await Task.yield() }
            return try ComparisonManager.compareLineRanges(left, right)
        }
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("expected CancellationError")
        } catch is CancellationError {
            return
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }
}

@Suite
struct LineFragmentTextTests {
    @Test
    func fragmentsCarryLineAndOffsetRanges() throws {
        let fragments = try ComparisonManager.compareLines("a\nb\nc", "a\nX\nc")

        #expect(fragments.count == 1)
        let fragment = try #require(fragments.first)
        #expect(fragment.startLine1 == 1)
        #expect(fragment.endLine1 == 2)
        #expect(fragment.startLine2 == 1)
        #expect(fragment.endLine2 == 2)
        #expect(fragment.startOffset1 == 2)
        #expect(fragment.endOffset1 == 4)
        #expect(fragment.startOffset2 == 2)
        #expect(fragment.endOffset2 == 4)
        #expect(fragment.innerFragments == nil)
    }

    @Test
    func trailingNewlineIsAnEmptyLastLine() throws {
        let fragments = try ComparisonManager.compareLines("x", "x\n")

        #expect(DiffEngineTestSupport.lineRanges(fragments) == [DiffEngineTestSupport.ins(1, 1, 1)])
    }

    @Test
    func wordLevelFragmentsMarkTheChangedWord() throws {
        let fragments = try ComparisonManager.compareWords("x z", "y z")

        #expect(DiffEngineTestSupport.offsetRanges(fragments) == [DiffRange(0, 1, 0, 1)])
    }

    @Test
    func innerLineFragmentsAreSplitOutOfTheLineBlock() throws {
        let fragments = try ComparisonManager.compareLinesInner("let x = 1", "let y = 1")

        #expect(fragments.count == 1)
        #expect(fragments.first?.innerFragments == [DiffFragment(4, 5, 4, 5)])
    }

    @Test
    func characterFragmentsMarkTheChangedCharacter() throws {
        let fragments = try ComparisonManager.compareChars("abcd", "abxd")

        #expect(DiffEngineTestSupport.offsetRanges(fragments) == [DiffRange(2, 3, 2, 3)])
    }

    @Test
    func offsetsAreUTF16Units() throws {
        let fragments = try ComparisonManager.compareChars("a😀b", "a😀c")

        #expect(DiffEngineTestSupport.offsetRanges(fragments) == [DiffRange(3, 4, 3, 4)])
    }
}
