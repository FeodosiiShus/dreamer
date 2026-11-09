import Testing
@testable import Dreamder

@Suite
struct ReindexerUnbalancedChangesTests {
    @Test
    func aChangeSetThatLeavesOneSideUnmatchedStopsReindexingInsteadOfLooping() {
        var reindexer = Reindexer()
        let discarded = reindexer.discardUnique([1, 1, 2, 9], [1, 2])
        var builder = LCSBuilder(startShift: 0)

        reindexer.reindex((DiffBitSet(), DiffBitSet()), into: &builder)

        #expect(discarded.first == [1, 1, 2])
        #expect(discarded.second == [1, 2])
        #expect(builder.ranges == [DiffRange(2, 4, 2, 2)])
    }

    @Test
    func theSameUnbalancedInputMirroredStopsTheSameWay() {
        var reindexer = Reindexer()
        let discarded = reindexer.discardUnique([1, 2], [1, 1, 2, 9])
        var builder = LCSBuilder(startShift: 0)

        reindexer.reindex((DiffBitSet(), DiffBitSet()), into: &builder)

        #expect(discarded.first == [1, 2])
        #expect(discarded.second == [1, 1, 2])
        #expect(builder.ranges == [DiffRange(2, 2, 2, 4)])
    }
}
