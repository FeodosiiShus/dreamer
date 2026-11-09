import Testing
@testable import Dreamder

@Suite
struct ThreeWayMergeCoverageTests {
    private func cancelledMerge(base: [String], left: [String], right: [String]) async -> ThreeWayMerge {
        await Task { () -> ThreeWayMerge in
            withUnsafeCurrentTask { (current: UnsafeCurrentTask?) in
                current?.cancel()
            }
            return ThreeWayMerge(baseLines: base, leftLines: left, rightLines: right)
        }.value
    }

    @Test
    func chipSymbolsMatchTheirKinds() {
        #expect(MergePaneChip(kind: .acceptLeft, blockID: 3).symbol == "\u{00BB}")
        #expect(MergePaneChip(kind: .acceptRight, blockID: 3).symbol == "\u{00AB}")
        #expect(MergePaneChip(kind: .ignore, blockID: 3).symbol == "\u{00D7}")
    }

    @Test
    func paneContentJoinsItsLines() {
        #expect(MergePaneContent.empty.text == "")
        #expect(MergePaneContent(lines: ["a", "b"], styles: [.unchanged, .changed], chips: [:]).text == "a\nb")
    }

    @Test
    func resolvingAnUnknownBlockChangesNothing() {
        var merge = ThreeWayMerge(
            baseLines: ["a", "b", "c"],
            leftLines: ["a", "L", "c"],
            rightLines: ["a", "R", "c"]
        )
        let before = merge

        merge.resolve(42, with: .left)

        #expect(merge == before)
        #expect(merge.conflictCount == 1)
    }

    @Test
    func identicalChangesFollowTheRequestedNonConflictingMode() {
        let merge = ThreeWayMerge(
            baseLines: ["a", "b", "c"],
            leftLines: ["a", "X", "c"],
            rightLines: ["a", "X", "c"]
        )
        #expect(merge.blocks.map(\.kind) == [.both])

        var right = merge
        right.applyNonConflicting(.right)
        #expect(right.blocks.map(\.resolution) == [.right])
        #expect(right.resultLines == ["a", "X", "c"])

        var left = merge
        left.applyNonConflicting(.left)
        #expect(left.blocks.map(\.resolution) == [.left])

        var all = merge
        all.applyNonConflicting(.all)
        #expect(all.blocks.map(\.resolution) == [.left])
    }

    @Test
    func applicableNonConflictingChangesDependOnTheMode() {
        let oursOnly = ThreeWayMerge(baseLines: ["a", "b"], leftLines: ["a", "B"], rightLines: ["a", "b"])
        #expect(oursOnly.hasApplicableNonConflictingChanges(.left))
        #expect(oursOnly.hasApplicableNonConflictingChanges(.all))
        #expect(oursOnly.hasApplicableNonConflictingChanges(.right) == false)

        let theirsOnly = ThreeWayMerge(baseLines: ["a", "b"], leftLines: ["a", "b"], rightLines: ["a", "B"])
        #expect(theirsOnly.hasApplicableNonConflictingChanges(.right))
        #expect(theirsOnly.hasApplicableNonConflictingChanges(.all))
        #expect(theirsOnly.hasApplicableNonConflictingChanges(.left) == false)

        let both = ThreeWayMerge(baseLines: ["a", "b"], leftLines: ["a", "X"], rightLines: ["a", "X"])
        #expect(both.hasApplicableNonConflictingChanges(.left))
        #expect(both.hasApplicableNonConflictingChanges(.right))

        let conflict = ThreeWayMerge(baseLines: ["a", "b"], leftLines: ["a", "L"], rightLines: ["a", "R"])
        #expect(conflict.hasApplicableNonConflictingChanges(.left) == false)
        #expect(conflict.hasApplicableNonConflictingChanges(.right) == false)
        #expect(conflict.hasApplicableNonConflictingChanges(.all) == false)
    }

    @Test
    func deletedSideKeepsItsChipsOnTheFollowingLine() {
        let merge = ThreeWayMerge(
            baseLines: ["a", "b", "c"],
            leftLines: ["a", "c"],
            rightLines: ["a", "B", "c"]
        )

        #expect(merge.blocks.map(\.kind) == [.conflict])
        #expect(merge.leftPane.lines == ["a", "c"])
        #expect(merge.leftPane.styles == [.unchanged, .unchanged])
        #expect(merge.leftPane.chips[1]?.map(\.kind) == [.acceptLeft, .ignore])
        #expect(merge.rightPane.lines == ["a", "B", "c"])
        #expect(merge.rightPane.chips[1]?.map(\.kind) == [.acceptRight, .ignore])
    }

    @Test
    func pendingChipsOfADeletedBlockAreFlushedBeforeTheNextBlock() {
        let merge = ThreeWayMerge(
            baseLines: ["a", "b", "c", "d", "e"],
            leftLines: ["a", "c", "d", "E"],
            rightLines: ["a", "B", "c", "d", "e"]
        )

        #expect(merge.blocks.map(\.kind) == [.conflict, .ours])
        #expect(merge.leftPane.lines == ["a", "c", "d", "E"])
        #expect(merge.leftPane.chips[1]?.map(\.kind) == [.acceptLeft, .ignore])
        #expect(merge.leftPane.chips[3]?.map(\.kind) == [.acceptLeft])
        #expect(merge.leftPane.chips[3]?.map(\.blockID) == [1])
    }

    @Test
    func deletionAtTheEndAttachesItsChipsToTheLastLine() {
        let merge = ThreeWayMerge(
            baseLines: ["a", "b"],
            leftLines: ["a"],
            rightLines: ["a", "B"]
        )

        #expect(merge.blocks.map(\.kind) == [.conflict])
        #expect(merge.leftPane.lines == ["a"])
        #expect(merge.leftPane.chips[0]?.map(\.kind) == [.acceptLeft, .ignore])
    }

    @Test
    func aChangeOnlyOnTheRightLeavesTheLeftPaneUnchanged() {
        let merge = ThreeWayMerge(
            baseLines: ["a", "b"],
            leftLines: ["a", "b"],
            rightLines: ["a", "B"]
        )

        #expect(merge.blocks.map(\.kind) == [.theirs])
        #expect(merge.leftPane.styles == [.unchanged, .unchanged])
        #expect(merge.rightPane.styles == [.unchanged, .changed])
    }

    @Test
    func cancelledComparisonFallsBackToOneCoarseConflict() async {
        let merge = await cancelledMerge(
            base: ["a", "b", "c"],
            left: ["a", "L", "c"],
            right: ["a", "R", "c"]
        )

        #expect(merge.blocks.count == 1)
        #expect(merge.blocks.first?.kind == .conflict)
        #expect(merge.blocks.first?.baseRange == 1..<2)
        #expect(merge.blocks.first?.leftLines == ["L"])
        #expect(merge.blocks.first?.rightLines == ["R"])
        #expect(merge.blocks.first?.canBeResolved == false)
        #expect(merge.conflictCount == 1)
    }

    @Test
    func coarseFallbackWithoutCommonLinesCoversEverything() async {
        let merge = await cancelledMerge(base: ["x"], left: ["y"], right: ["z"])

        #expect(merge.blocks.map(\.baseRange) == [0..<1])
        #expect(merge.blocks.first?.leftRange == 0..<1)
        #expect(merge.blocks.first?.rightRange == 0..<1)
    }

    @Test
    func coarseFallbackKeepsTheCommonPrefixOfDifferentLengths() async {
        let merge = await cancelledMerge(base: ["a"], left: ["a", "b"], right: ["a"])

        #expect(merge.blocks.count == 1)
        #expect(merge.blocks.first?.baseRange == 1..<1)
        #expect(merge.blocks.first?.leftLines == ["b"])
        #expect(merge.blocks.first?.rightLines.isEmpty == true)
    }

    @Test
    func coarseFallbackOfIdenticalTextsHasNoBlocks() async {
        let merge = await cancelledMerge(base: ["a", "b"], left: ["a", "b"], right: ["a", "b"])

        #expect(merge.blocks.isEmpty)
        #expect(merge.resultLines == ["a", "b"])
        #expect(merge.isFullyResolved)
    }
}
