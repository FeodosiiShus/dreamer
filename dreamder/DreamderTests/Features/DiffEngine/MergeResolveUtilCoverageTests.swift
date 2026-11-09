import Testing
import Foundation
@testable import Dreamder

@Suite struct MergeResolveUtilCoverageTests {
    @Test func cancelledResolveGivesUpWithoutResult() async {
        let task = Task { () async -> String? in
            while !Task.isCancelled { await Task.yield() }
            return MergeResolveUtil.tryResolve(left: "x b c", base: "a b c", right: "a b y")
        }
        task.cancel()

        #expect(await task.value == nil)
    }

    @Test func notCancelledResolveCombinesDisjointEdits() {
        #expect(MergeResolveUtil.tryResolve(left: "x b c", base: "a b c", right: "a b y") == "x b y")
    }

    @Test func conflictOnlyResolvableWhenIgnoringWhitespacesUsesTheSecondPass() {
        #expect(MergeResolveUtil.tryResolve(left: "a  b", base: "a b", right: "a b c") == "a  b c")
    }

    @Test func utf16ResolutionMatchesTheStringOverload() {
        let left = Array("x b c".utf16)
        let base = Array("a b c".utf16)
        let right = Array("a b y".utf16)

        #expect(MergeResolveUtil.tryResolve(left: left, base: base, right: right) == Array("x b y".utf16))
    }

    @Test func comparisonMergeUtilDelegatesToTheResolver() {
        let left = Array("x b c".utf16)
        let base = Array("a b c".utf16)
        let right = Array("a b y".utf16)
        let conflicting = Array("c".utf16)

        #expect(ComparisonMergeUtil.tryResolveConflict(left: left, base: base, right: right) == Array("x b y".utf16))
        #expect(ComparisonMergeUtil.tryResolveConflict(left: Array("b".utf16), base: Array("a".utf16), right: conflicting) == nil)
    }
}
