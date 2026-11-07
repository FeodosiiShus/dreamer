import Testing
@testable import Dreamder

@Suite
struct ThreeWayMergeTests {
    @Test
    func appliesLeftOnlyChange() {
        let merge = ThreeWayMerge(
            baseLines: ["a", "b", "c"],
            leftLines: ["a", "B", "c"],
            rightLines: ["a", "b", "c"]
        )
        #expect(merge.blocks.count == 1)
        #expect(merge.blocks.first?.kind == .ours)
        #expect(merge.resultLines == ["a", "B", "c"])
        #expect(merge.conflictCount == 0)
        #expect(merge.changeCount == 1)
        #expect(merge.summary == "1 change, 0 conflicts")
    }

    @Test
    func appliesRightOnlyChange() {
        let merge = ThreeWayMerge(
            baseLines: ["a", "b", "c"],
            leftLines: ["a", "b", "c"],
            rightLines: ["a", "b", "C"]
        )
        #expect(merge.blocks.first?.kind == .theirs)
        #expect(merge.resultLines == ["a", "b", "C"])
    }

    @Test
    func appliesIdenticalChangeFromBothSides() {
        let merge = ThreeWayMerge(
            baseLines: ["a", "b", "c"],
            leftLines: ["a", "X", "c"],
            rightLines: ["a", "X", "c"]
        )
        #expect(merge.blocks.first?.kind == .both)
        #expect(merge.resultLines == ["a", "X", "c"])
        #expect(merge.conflictCount == 0)
    }

    @Test
    func detectsTrueConflict() {
        let merge = ThreeWayMerge(
            baseLines: ["a", "b", "c"],
            leftLines: ["a", "L", "c"],
            rightLines: ["a", "R", "c"]
        )
        #expect(merge.blocks.count == 1)
        #expect(merge.blocks.first?.kind == .conflict)
        #expect(merge.blocks.first?.resolution == .unresolved)
        #expect(merge.resultLines == ["a", "b", "c"])
        #expect(merge.conflictCount == 1)
        #expect(merge.isFullyResolved == false)
        #expect(merge.summary == "0 changes, 1 conflict")
    }

    @Test
    func resolvesConflictToLeft() {
        var merge = ThreeWayMerge(
            baseLines: ["a", "b", "c"],
            leftLines: ["a", "L", "c"],
            rightLines: ["a", "R", "c"]
        )
        merge.resolve(0, with: .left)
        #expect(merge.resultLines == ["a", "L", "c"])
        #expect(merge.conflictCount == 0)
        #expect(merge.isFullyResolved)
    }

    @Test
    func resolvesConflictToRight() {
        var merge = ThreeWayMerge(
            baseLines: ["a", "b", "c"],
            leftLines: ["a", "L", "c"],
            rightLines: ["a", "R", "c"]
        )
        merge.resolve(0, with: .right)
        #expect(merge.resultLines == ["a", "R", "c"])
    }

    @Test
    func ignoresConflict() {
        var merge = ThreeWayMerge(
            baseLines: ["a", "b", "c"],
            leftLines: ["a", "L", "c"],
            rightLines: ["a", "R", "c"]
        )
        merge.resolve(0, with: .ignored)
        #expect(merge.resultLines == ["a", "b", "c"])
        #expect(merge.conflictCount == 0)
        #expect(merge.resultPane.styles == [.unchanged, .unchanged, .unchanged])
    }

    @Test
    func detectsInsertionAtEnd() {
        let merge = ThreeWayMerge(
            baseLines: ["a", "b"],
            leftLines: ["a", "b", "l"],
            rightLines: ["a", "b"]
        )
        #expect(merge.blocks.first?.kind == .ours)
        #expect(merge.blocks.first?.inserted == true)
        #expect(merge.resultLines == ["a", "b", "l"])
        #expect(merge.leftPane.styles.last == .inserted)
    }

    @Test
    func identicalInsertionAtEndIsNotAConflict() {
        let merge = ThreeWayMerge(
            baseLines: ["a", "b"],
            leftLines: ["a", "b", "x"],
            rightLines: ["a", "b", "x"]
        )
        #expect(merge.blocks.first?.kind == .both)
        #expect(merge.resultLines == ["a", "b", "x"])
        #expect(merge.conflictCount == 0)
    }

    @Test
    func differentInsertionsAtEndConflict() {
        let merge = ThreeWayMerge(
            baseLines: ["a", "b"],
            leftLines: ["a", "b", "l"],
            rightLines: ["a", "b", "r"]
        )
        #expect(merge.blocks.first?.kind == .conflict)
        #expect(merge.resultLines == ["a", "b"])
        #expect(merge.blocks.first?.leftLines == ["l"])
        #expect(merge.blocks.first?.rightLines == ["r"])
    }

    @Test
    func keepsTrailingNewline() {
        let merge = ThreeWayMerge(base: "a\nb\n", ours: "a\nB\n", theirs: "a\nb\n")
        #expect(merge.resultText == "a\nB\n")

        let without = ThreeWayMerge(base: "a\nb", ours: "a\nB", theirs: "a\nb")
        #expect(without.resultText == "a\nB")
    }

    @Test
    func independentChangesOnBothSides() {
        let merge = ThreeWayMerge(
            baseLines: ["a", "b", "c", "d"],
            leftLines: ["A", "b", "c", "d"],
            rightLines: ["a", "b", "c", "D"]
        )
        #expect(merge.blocks.count == 2)
        #expect(merge.conflictCount == 0)
        #expect(merge.resultLines == ["A", "b", "c", "D"])
    }

    @Test
    func insertionNextToModifiedLineIsAConflict() {
        var merge = ThreeWayMerge(
            baseLines: ["a", "b", "c"],
            leftLines: ["a", "x", "b", "c"],
            rightLines: ["a", "B", "c"]
        )
        #expect(merge.blocks.count == 1)
        #expect(merge.blocks.first?.kind == .conflict)
        #expect(merge.blocks.first?.baseRange == 1..<2)
        #expect(merge.blocks.first?.leftLines == ["x", "b"])
        #expect(merge.blocks.first?.rightLines == ["B"])
        #expect(merge.blocks.first?.canBeResolved == false)
        #expect(merge.conflictCount == 1)
        #expect(merge.resultLines == ["a", "b", "c"])

        var right = merge
        right.resolve(0, with: .right)
        #expect(right.resultLines == ["a", "B", "c"])

        merge.resolve(0, with: .left)
        #expect(merge.resultLines == ["a", "x", "b", "c"])
    }

    @Test
    func deleteVersusModifyIsConflict() {
        let merge = ThreeWayMerge(
            baseLines: ["a", "b", "c"],
            leftLines: ["a", "c"],
            rightLines: ["a", "B", "c"]
        )
        #expect(merge.blocks.first?.kind == .conflict)
        var resolved = merge
        resolved.resolve(0, with: .left)
        #expect(resolved.resultLines == ["a", "c"])
    }

    @Test
    func appliesNonConflictingFromOneSide() {
        let merge = ThreeWayMerge(
            baseLines: ["a", "b", "c", "d"],
            leftLines: ["A", "b", "c", "d"],
            rightLines: ["a", "b", "c", "D"]
        )

        var left = merge
        left.applyNonConflicting(.left)
        #expect(left.resultLines == ["A", "b", "c", "d"])
        #expect(left.changeCount == 1)

        var right = merge
        right.applyNonConflicting(.right)
        #expect(right.resultLines == ["a", "b", "c", "D"])

        var all = left
        all.applyNonConflicting(.all)
        #expect(all.resultLines == ["A", "b", "c", "D"])
    }

    @Test
    func buildsPaneContents() {
        let merge = ThreeWayMerge(
            baseLines: ["a", "b", "c"],
            leftLines: ["a", "L", "c"],
            rightLines: ["a", "R", "c"]
        )

        #expect(merge.leftPane.lines == ["a", "L", "c"])
        #expect(merge.leftPane.styles == [.unchanged, .conflict, .unchanged])
        #expect(merge.rightPane.lines == ["a", "R", "c"])
        #expect(merge.rightPane.styles == [.unchanged, .conflict, .unchanged])
        #expect(merge.resultPane.lines == ["a", "b", "c"])
        #expect(merge.resultPane.styles == [.unchanged, .conflict, .unchanged])

        var resolved = merge
        resolved.resolve(0, with: .right)
        #expect(resolved.resultPane.lines == ["a", "R", "c"])
        #expect(resolved.resultPane.styles == [.unchanged, .resolved, .unchanged])
    }

    @Test
    func paneChipsExposeBlockActions() {
        let merge = ThreeWayMerge(
            baseLines: ["a", "b", "c"],
            leftLines: ["a", "L", "c"],
            rightLines: ["a", "R", "c"]
        )

        let leftChips = merge.leftPane.chips[1] ?? []
        #expect(leftChips.map(\.kind) == [.acceptLeft, .ignore])
        #expect(leftChips.first?.blockID == 0)

        let rightChips = merge.rightPane.chips[1] ?? []
        #expect(rightChips.map(\.kind) == [.acceptRight, .ignore])

        let change = ThreeWayMerge(
            baseLines: ["a", "b", "c"],
            leftLines: ["a", "B", "c"],
            rightLines: ["a", "b", "c"]
        )
        #expect((change.leftPane.chips[1] ?? []).map(\.kind) == [.acceptLeft])
        #expect(change.leftPane.styles[1] == .changed)
    }

    @Test
    func resolvesEveryBlockToWholeSide() {
        let merge = ThreeWayMerge(
            baseLines: ["a", "b", "c", "d"],
            leftLines: ["A", "b", "L", "d"],
            rightLines: ["a", "R", "c", "D"]
        )

        var left = merge
        for block in merge.blocks {
            left.resolve(block.id, with: .left)
        }
        #expect(left.resultText.hasPrefix("A\n"))
        #expect(left.resultLines.count == 4)

        var right = merge
        for block in merge.blocks {
            right.resolve(block.id, with: .right)
        }
        #expect(right.resultLines == ["a", "R", "c", "D"])
    }

    @Test
    func modificationAndAppendedLineOfOppositeSidesFormOneConflict() {
        let merge = ThreeWayMerge(
            baseLines: ["a", "b"],
            leftLines: ["a", "B"],
            rightLines: ["a", "b", "c"]
        )

        #expect(merge.blocks.count == 1)
        #expect(merge.blocks.first?.kind == .conflict)
        #expect(merge.blocks.first?.baseRange == 1..<2)
        #expect(merge.blocks.first?.leftLines == ["B"])
        #expect(merge.blocks.first?.rightLines == ["b", "c"])
        #expect(merge.blocks.first?.canBeResolved == false)
    }

    @Test
    func changesSeparatedByUnchangedLineStayIndependent() {
        let merge = ThreeWayMerge(
            baseLines: ["a", "b", "c", "d"],
            leftLines: ["a", "B", "c", "d"],
            rightLines: ["a", "b", "c", "D"]
        )

        #expect(merge.blocks.map(\.kind) == [.ours, .theirs])
        #expect(merge.blocks.map(\.baseRange) == [1..<2, 3..<4])
    }

    @Test
    func resolvesChangesToDifferentWordsOfTheSameLine() {
        var merge = ThreeWayMerge(
            baseLines: ["a", "foo bar baz", "c"],
            leftLines: ["a", "FOO bar baz", "c"],
            rightLines: ["a", "foo bar BAZ", "c"]
        )

        #expect(merge.blocks.count == 1)
        #expect(merge.blocks.first?.kind == .conflict)
        #expect(merge.blocks.first?.canBeResolved == true)
        #expect(merge.blocks.first?.autoResolvedLines == ["FOO bar BAZ"])
        #expect(merge.conflictCount == 1)
        #expect(merge.resolvableConflictCount == 1)
        #expect(merge.hasResolvableConflicts)
        #expect(merge.resultLines == ["a", "foo bar baz", "c"])

        merge.resolveSimpleConflicts()

        #expect(merge.blocks.first?.resolution == .merged)
        #expect(merge.conflictCount == 0)
        #expect(merge.isFullyResolved)
        #expect(merge.resolvableConflictCount == 0)
        #expect(merge.resultLines == ["a", "FOO bar BAZ", "c"])
        #expect(merge.resultPane.lines == ["a", "FOO bar BAZ", "c"])
        #expect(merge.resultPane.styles == [.unchanged, .resolved, .unchanged])
    }

    @Test
    func resolveSimpleConflictsLeavesRealConflictsUntouched() {
        var merge = ThreeWayMerge(
            baseLines: ["x", "foo bar baz", "y", "one", "z"],
            leftLines: ["x", "FOO bar baz", "y", "two", "z"],
            rightLines: ["x", "foo bar BAZ", "y", "three", "z"]
        )

        #expect(merge.blocks.count == 2)
        #expect(merge.blocks.map(\.canBeResolved) == [true, false])
        #expect(merge.conflictCount == 2)

        merge.resolveSimpleConflicts()

        #expect(merge.blocks.map(\.resolution) == [.merged, .unresolved])
        #expect(merge.conflictCount == 1)
        #expect(merge.resultLines == ["x", "FOO bar BAZ", "y", "one", "z"])
    }

    @Test
    func mergedResolutionIsRejectedForConflictsThatCannotBeResolved() {
        var merge = ThreeWayMerge(
            baseLines: ["a", "b", "c"],
            leftLines: ["a", "L", "c"],
            rightLines: ["a", "R", "c"]
        )

        merge.resolve(0, with: .merged)

        #expect(merge.blocks.first?.resolution == .unresolved)
        #expect(merge.conflictCount == 1)
    }

    @Test
    func choosingASideAfterMergedResolutionReplacesIt() {
        var merge = ThreeWayMerge(
            baseLines: ["a", "foo bar baz", "c"],
            leftLines: ["a", "FOO bar baz", "c"],
            rightLines: ["a", "foo bar BAZ", "c"]
        )
        merge.resolveSimpleConflicts()
        merge.resolve(0, with: .right)

        #expect(merge.blocks.first?.resolution == .right)
        #expect(merge.resultLines == ["a", "foo bar BAZ", "c"])
    }

    @Test
    func whitespaceOnlyChangeOnOneSideIsKeptAsOneSidedChangeWhenIgnoringWhitespaces() {
        let merge = ThreeWayMerge(
            base: "a\nb b\nc\n",
            ours: "a\nb  b\nc\n",
            theirs: "a\nb b\nc\n",
            policy: .ignoreWhitespaces
        )

        #expect(merge.blocks.count == 1)
        #expect(merge.blocks.first?.kind == .ours)
        #expect(merge.blocks.first?.leftLines == ["b  b"])
        #expect(merge.conflictCount == 0)
    }
}
