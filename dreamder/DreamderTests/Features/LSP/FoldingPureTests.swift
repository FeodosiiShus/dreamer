import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct FoldLineIndexTests {
    @Test
    func lineFeedsSplitLinesAndKeepEmptyLinesAndTheLastLine() {
        let index = FoldLineIndex(text: "a\nbb\n\nccc")

        #expect(index.lineCount == 4)
        #expect((0..<4).compactMap { index.start(ofLine: $0) } == [0, 2, 5, 6])
        #expect((0..<4).compactMap { index.contentEnd(ofLine: $0) } == [1, 4, 5, 9])
        #expect(index.lineRanges == [0..<1, 2..<4, 5..<5, 6..<9])
    }

    @Test
    func trailingLineFeedStartsAnEmptyLastLine() {
        let index = FoldLineIndex(text: "a\n")

        #expect(index.lineCount == 2)
        #expect(index.start(ofLine: 1) == 2)
        #expect(index.contentEnd(ofLine: 1) == 2)
    }

    @Test
    func carriageReturnsAndCarriageReturnLineFeedsAreSingleLineBreaks() {
        let index = FoldLineIndex(text: "a\rb\r\nc\n")

        #expect(index.lineCount == 4)
        #expect((0..<4).compactMap { index.start(ofLine: $0) } == [0, 2, 5, 7])
        #expect((0..<4).compactMap { index.contentEnd(ofLine: $0) } == [1, 3, 6, 7])
    }

    @Test
    func emptyTextHasOneEmptyLine() {
        let index = FoldLineIndex(text: "")

        #expect(index.lineCount == 1)
        #expect(index.start(ofLine: 0) == 0)
        #expect(index.contentEnd(ofLine: 0) == 0)
    }

    @Test
    func accessorsReturnNilOutsideTheDocument() {
        let index = FoldLineIndex(text: "a\nb")

        #expect(index.start(ofLine: -1) == nil)
        #expect(index.start(ofLine: 2) == nil)
        #expect(index.contentEnd(ofLine: -1) == nil)
        #expect(index.contentEnd(ofLine: 2) == nil)
    }

    @Test
    func lineContainingAnOffsetIncludesTheTerminatorAndClamps() {
        let index = FoldLineIndex(text: "ab\ncd\nef")

        #expect(index.line(containing: -5) == 0)
        #expect(index.line(containing: 0) == 0)
        #expect(index.line(containing: 2) == 0)
        #expect(index.line(containing: 3) == 1)
        #expect(index.line(containing: 5) == 1)
        #expect(index.line(containing: 6) == 2)
        #expect(index.line(containing: 99) == 2)
    }

    @Test
    func hiddenRangeRunsFromTheEndOfTheStartLineToTheEndOfTheEndLine() {
        let index = FoldLineIndex(text: "func a() {\n    one\n    two\n}\n")

        let hidden = index.hiddenRange(of: FoldRegion(startLine: 0, endLine: 2, kind: .block))

        #expect(hidden == NSRange(location: 10, length: 16))
    }

    @Test
    func hiddenRangeIsNilForRegionsWithoutHiddenLinesOrOutsideTheDocument() {
        let index = FoldLineIndex(text: "a\nb\nc")

        #expect(index.hiddenRange(of: FoldRegion(startLine: 1, endLine: 1, kind: .block)) == nil)
        #expect(index.hiddenRange(of: FoldRegion(startLine: 2, endLine: 1, kind: .block)) == nil)
        #expect(index.hiddenRange(of: FoldRegion(startLine: 0, endLine: 3, kind: .block)) == nil)
        #expect(index.hiddenRange(of: FoldRegion(startLine: 5, endLine: 6, kind: .block)) == nil)
    }

    @Test
    func textRangeCoversWholeLinesOfTheRegion() {
        let index = FoldLineIndex(text: "ab\ncd\nef")

        #expect(index.textRange(of: FoldRegion(startLine: 0, endLine: 1, kind: .block)) == NSRange(location: 0, length: 5))
        #expect(index.textRange(of: FoldRegion(startLine: 1, endLine: 1, kind: .block)) == NSRange(location: 3, length: 2))
        #expect(index.textRange(of: FoldRegion(startLine: 2, endLine: 1, kind: .block)) == nil)
        #expect(index.textRange(of: FoldRegion(startLine: 3, endLine: 4, kind: .block)) == nil)
        #expect(index.textRange(of: FoldRegion(startLine: 0, endLine: 3, kind: .block)) == nil)
    }
}

@MainActor
@Suite(.uiGate)
struct FoldRegionMappingTests {
    @Test
    func kindsMapOneToOneAndMissingKindIsAGenericBlock() {
        #expect(FoldRegionMapping.kind(of: .imports) == .imports)
        #expect(FoldRegionMapping.kind(of: .comment) == .comment)
        #expect(FoldRegionMapping.kind(of: .region) == .region)
        #expect(FoldRegionMapping.kind(of: nil) == .block)
    }

    @Test
    func lineFoldingOnlyRangesIgnoreCharactersAndKeepKinds() {
        let ranges = [
            FoldingRange(startLine: 0, startCharacter: 4, endLine: 1, endCharacter: 9, kind: .imports),
            FoldingRange(startLine: 3, endLine: 6, kind: .comment),
            FoldingRange(startLine: 8, endLine: 9, kind: .region),
            FoldingRange(startLine: 11, endLine: 12)
        ]

        let regions = FoldRegionMapping.regions(from: ranges, lineCount: 20)

        #expect(regions == [
            FoldRegion(startLine: 0, endLine: 1, kind: .imports),
            FoldRegion(startLine: 3, endLine: 6, kind: .comment),
            FoldRegion(startLine: 8, endLine: 9, kind: .region),
            FoldRegion(startLine: 11, endLine: 12, kind: .block)
        ])
    }

    @Test
    func invalidRangesAreDroppedAndTheEndIsClampedToTheLastLine() {
        let ranges = [
            FoldingRange(startLine: -1, endLine: 3),
            FoldingRange(startLine: 10, endLine: 12),
            FoldingRange(startLine: 4, endLine: 4),
            FoldingRange(startLine: 5, endLine: 3),
            FoldingRange(startLine: 6, endLine: 400)
        ]

        let regions = FoldRegionMapping.regions(from: ranges, lineCount: 10)

        #expect(regions == [FoldRegion(startLine: 6, endLine: 9, kind: .block)])
    }

    @Test
    func duplicateSpansKeepTheFirstKindAndTheResultIsOrderedOuterFirst() {
        let ranges = [
            FoldingRange(startLine: 4, endLine: 5),
            FoldingRange(startLine: 0, endLine: 8, kind: .region),
            FoldingRange(startLine: 0, endLine: 8, kind: .comment),
            FoldingRange(startLine: 0, endLine: 3),
            FoldingRange(startLine: 4, endLine: 5, kind: .imports)
        ]

        let regions = FoldRegionMapping.regions(from: ranges, lineCount: 10)

        #expect(regions == [
            FoldRegion(startLine: 0, endLine: 8, kind: .region),
            FoldRegion(startLine: 0, endLine: 3, kind: .block),
            FoldRegion(startLine: 4, endLine: 5, kind: .block)
        ])
    }

    @Test
    func noRangesMapToNoRegions() {
        #expect(FoldRegionMapping.regions(from: [], lineCount: 10).isEmpty)
    }

    @Test
    func intelliJFoldingUtilTestFoldTreeIteratorOrder() {
        let regions = [
            FoldRegion(startLine: 10, endLine: 11, kind: .block),
            FoldRegion(startLine: 7, endLine: 10, kind: .block),
            FoldRegion(startLine: 0, endLine: 5, kind: .block),
            FoldRegion(startLine: 1, endLine: 2, kind: .block),
            FoldRegion(startLine: 0, endLine: 10, kind: .block)
        ]

        let ordered = FoldRegion.sortedOuterFirst(regions).map { "\($0.startLine),\($0.endLine)" }

        #expect(ordered.joined(separator: "|") == "0,10|0,5|1,2|7,10|10,11")
    }
}

@MainActor
@Suite(.uiGate)
struct IndentationFoldComputerTests {
    private func spans(_ text: String, tabWidth: Int = 4) -> [String] {
        IndentationFoldComputer.regions(in: text, tabWidth: tabWidth).map { "\($0.startLine)-\($0.endLine)" }
    }

    @Test
    func nestedBlocksFoldUpToTheirLastDeeperLine() {
        let text = "a\n  b\n    c\n    d\n  e\nf\n"

        #expect(spans(text) == ["0-4", "1-3"])
    }

    @Test
    func regionsAreOrderedOuterFirstAndKindIsBlock() {
        let text = "a\n b\n  c\nd\n e\n"

        let regions = IndentationFoldComputer.regions(in: text, tabWidth: 4)

        #expect(regions == [
            FoldRegion(startLine: 0, endLine: 2, kind: .block),
            FoldRegion(startLine: 1, endLine: 2, kind: .block),
            FoldRegion(startLine: 3, endLine: 4, kind: .block)
        ])
    }

    @Test
    func blankAndWhitespaceOnlyLinesAreTransparent() {
        let text = "a\n  b\n\n   \n  c\n\nd\n"

        #expect(spans(text) == ["0-4"])
    }

    @Test
    func trailingBlankLinesAreNotPartOfTheRegion() {
        let text = "a\n  b\n\n\n"

        #expect(spans(text) == ["0-1"])
    }

    @Test
    func aTrailingBlockAtTheEndOfTheFileWithoutNewlineFolds() {
        #expect(spans("a\n  b\n  c") == ["0-2"])
        #expect(spans("a\n  b\n  c\n") == ["0-2"])
    }

    @Test
    func singleLinesAndEmptyTextHaveNoRegions() {
        #expect(spans("").isEmpty)
        #expect(spans("a").isEmpty)
        #expect(spans("a\nb\nc\n").isEmpty)
        #expect(spans("\n\n  \n").isEmpty)
    }

    @Test
    func siblingBlocksAtTheSameLevelAreSeparateRegions() {
        let text = "if x:\n    a\nelse:\n    b\n"

        #expect(spans(text) == ["0-1", "2-3"])
    }

    @Test
    func dedentingSeveralLevelsClosesAllOpenBlocks() {
        let text = "a\n b\n  c\n   d\ne\n"

        #expect(spans(text) == ["0-3", "1-3", "2-3"])
    }

    @Test
    func tabsAdvanceToTheNextTabStopAndAgreeWithEquivalentSpaces() {
        #expect(spans("a\n\tb\n\tc\nd\n") == ["0-2"])
        #expect(spans("a\n\tb\n    c\n") == ["0-2"])
        #expect(spans("a\n  \tb\n    c\n") == ["0-2"])
    }

    @Test
    func tabWidthDecidesWhichMixedIndentIsDeeper() {
        let text = "a\n    b\n\tc\n"

        #expect(spans(text, tabWidth: 8) == ["0-2", "1-2"])
        #expect(spans(text, tabWidth: 4) == ["0-2"])
    }

    @Test
    func nonPositiveTabWidthCountsATabAsOneColumn() {
        #expect(spans("a\n\tb\n", tabWidth: 0) == ["0-1"])
        #expect(spans("a\n b\n\tc\n", tabWidth: -3) == ["0-2"])
    }

    @Test
    func carriageReturnLineEndingsAreSupported() {
        #expect(spans("a\r\n  b\r\n  c\r\nd\r\n") == ["0-2"])
    }

    @Test
    func resolverPrefersServerRangesAndFallsBackToIndentation() async {
        let text = "a\n  b\n  c\nd\n"
        let server = [FoldingRange(startLine: 1, endLine: 2, kind: .comment)]

        let fromServer = await FoldRegionResolver.regions(serverRanges: server, text: text, tabWidth: 4)
        let withoutServer = await FoldRegionResolver.regions(serverRanges: nil, text: text, tabWidth: 4)
        let emptyServer = await FoldRegionResolver.regions(serverRanges: [], text: text, tabWidth: 4)
        let unusableServer = await FoldRegionResolver.regions(
            serverRanges: [FoldingRange(startLine: 50, endLine: 60)],
            text: text,
            tabWidth: 4
        )

        #expect(fromServer == [FoldRegion(startLine: 1, endLine: 2, kind: .comment)])
        #expect(withoutServer == [FoldRegion(startLine: 0, endLine: 2, kind: .block)])
        #expect(emptyServer == withoutServer)
        #expect(unusableServer == withoutServer)
    }
}

@MainActor
@Suite(.uiGate)
struct FoldCommandPlannerTests {
    private let outer = FoldRegion(startLine: 0, endLine: 10, kind: .block)
    private let middle = FoldRegion(startLine: 2, endLine: 5, kind: .block)
    private let inner = FoldRegion(startLine: 3, endLine: 4, kind: .block)
    private let late = FoldRegion(startLine: 7, endLine: 9, kind: .block)

    private var regions: [FoldRegion] {
        [outer, middle, inner, late]
    }

    private func collapsed(_ set: [FoldRegion]) -> (FoldRegion) -> Bool {
        { set.contains($0) }
    }

    @Test
    func regionStartingAtALineMustBeUnique() {
        let sibling = FoldRegion(startLine: 2, endLine: 3, kind: .block)

        #expect(FoldCommandPlanner.regionStarting(atLine: 2, in: regions) == middle)
        #expect(FoldCommandPlanner.regionStarting(atLine: 1, in: regions) == nil)
        #expect(FoldCommandPlanner.regionStarting(atLine: 2, in: regions + [sibling]) == nil)
    }

    @Test
    func regionsContainingALineAreOrderedInnermostFirst() {
        let sameStart = FoldRegion(startLine: 3, endLine: 8, kind: .block)

        #expect(FoldCommandPlanner.regionsContaining(line: 3, in: regions) == [inner, middle, outer])
        #expect(FoldCommandPlanner.regionsContaining(line: 8, in: regions) == [late, outer])
        #expect(FoldCommandPlanner.regionsContaining(line: 11, in: regions).isEmpty)
        #expect(FoldCommandPlanner.regionsContaining(line: 4, in: regions + [sameStart]) == [inner, sameStart, middle, outer])
    }

    @Test
    func collapseRegionActionCollapsesTheRegionStartingAtTheCaretLine() {
        let target = FoldCommandPlanner.regionToCollapse(regions: regions, caretLine: 3, isCollapsed: collapsed([]))

        #expect(target == inner)
    }

    @Test
    func collapseRegionActionFallsBackToTheInnermostExpandedRegionAroundTheCaret() {
        let target = FoldCommandPlanner.regionToCollapse(regions: regions, caretLine: 8, isCollapsed: collapsed([]))
        let nested = FoldCommandPlanner.regionToCollapse(regions: regions, caretLine: 4, isCollapsed: collapsed([]))

        #expect(target == late)
        #expect(nested == inner)
    }

    @Test
    func collapseRegionActionSkipsCollapsedRegionsAndMovesOutward() {
        let afterInner = FoldCommandPlanner.regionToCollapse(
            regions: regions,
            caretLine: 3,
            isCollapsed: collapsed([inner])
        )
        let afterAll = FoldCommandPlanner.regionToCollapse(
            regions: regions,
            caretLine: 3,
            isCollapsed: collapsed([inner, middle, outer])
        )

        #expect(afterInner == middle)
        #expect(afterAll == nil)
    }

    @Test
    func collapseDoesNothingWhenTheCaretIsInsideACollapsedRegionOrOutsideAllRegions() {
        let hidden = FoldCommandPlanner.regionToCollapse(
            regions: regions,
            caretLine: 4,
            isCollapsed: collapsed([middle])
        )
        let outside = FoldCommandPlanner.regionToCollapse(regions: regions, caretLine: 12, isCollapsed: collapsed([]))

        #expect(hidden == nil)
        #expect(outside == nil)
    }

    @Test
    func collapseOnTheStartLineOfACollapsedRegionStillCollapsesTheEnclosingRegion() {
        let target = FoldCommandPlanner.regionToCollapse(
            regions: regions,
            caretLine: 2,
            isCollapsed: collapsed([middle])
        )

        #expect(target == outer)
    }

    @Test
    func collapseWithAmbiguousStartLinesUsesTheInnermostContainingRegion() {
        let sibling = FoldRegion(startLine: 2, endLine: 3, kind: .block)

        let target = FoldCommandPlanner.regionToCollapse(
            regions: regions + [sibling],
            caretLine: 2,
            isCollapsed: collapsed([])
        )

        #expect(target == sibling)
    }

    @Test
    func expandRegionActionExpandsTheCollapsedRegionStartingAtTheCaretLine() {
        let target = FoldCommandPlanner.regionToExpand(
            regions: regions,
            caretLine: 2,
            isCollapsed: collapsed([middle, outer])
        )

        #expect(target == middle)
    }

    @Test
    func expandRegionActionFallsBackToTheOutermostCollapsedRegionContainingTheCaret() {
        let target = FoldCommandPlanner.regionToExpand(
            regions: regions,
            caretLine: 2,
            isCollapsed: collapsed([outer])
        )
        let deep = FoldCommandPlanner.regionToExpand(
            regions: regions,
            caretLine: 3,
            isCollapsed: collapsed([middle, outer])
        )

        #expect(target == outer)
        #expect(deep == outer)
    }

    @Test
    func expandDoesNothingWithoutACollapsedRegionAtTheCaret() {
        let none = FoldCommandPlanner.regionToExpand(regions: regions, caretLine: 3, isCollapsed: collapsed([]))
        let elsewhere = FoldCommandPlanner.regionToExpand(regions: regions, caretLine: 8, isCollapsed: collapsed([middle]))

        #expect(none == nil)
        #expect(elsewhere == nil)
    }

    @Test
    func selectionScopesRegionsToThoseFullyInsideIt() {
        let index = FoldLineIndex(text: String(repeating: "xx\n", count: 12))
        let selection = NSRange(location: 9, length: 6)

        let scoped = FoldCommandPlanner.regionsForSelection(regions: regions, selection: selection, index: index)
        let wider = FoldCommandPlanner.regionsForSelection(
            regions: regions,
            selection: NSRange(location: 6, length: 12),
            index: index
        )

        #expect(scoped == [inner])
        #expect(wider == [middle, inner])
    }

    @Test
    func missingEmptyOrUnmatchedSelectionsUseAllRegions() {
        let index = FoldLineIndex(text: String(repeating: "xx\n", count: 12))

        #expect(FoldCommandPlanner.regionsForSelection(regions: regions, selection: nil, index: index) == regions)
        #expect(
            FoldCommandPlanner.regionsForSelection(
                regions: regions,
                selection: NSRange(location: 6, length: 0),
                index: index
            ) == regions
        )
        #expect(
            FoldCommandPlanner.regionsForSelection(
                regions: regions,
                selection: NSRange(location: 0, length: 4),
                index: index
            ) == regions
        )
    }

    @Test
    func regionsOutsideTheDocumentAreNeverInsideASelection() {
        let index = FoldLineIndex(text: "a\nb\nc\n")
        let beyond = FoldRegion(startLine: 20, endLine: 30, kind: .block)

        let scoped = FoldCommandPlanner.regionsForSelection(
            regions: [beyond],
            selection: NSRange(location: 0, length: 6),
            index: index
        )

        #expect(scoped == [beyond])
    }

    @Test
    func collapseAllTakesOnlyExpandedRegions() {
        let result = FoldCommandPlanner.regionsToCollapse(scope: regions, isCollapsed: collapsed([middle, late]))

        #expect(result == [outer, inner])
    }

    @Test
    func commentRegionsAreTheExpandedCommentKindOnly() {
        let docs = FoldRegion(startLine: 0, endLine: 3, kind: .comment)
        let line = FoldRegion(startLine: 5, endLine: 6, kind: .comment)
        let imports = FoldRegion(startLine: 8, endLine: 9, kind: .imports)

        let result = FoldCommandPlanner.commentRegions(
            in: [docs, line, imports, inner],
            isCollapsed: collapsed([line])
        )

        #expect(result == [docs])
        #expect(FoldCommandPlanner.commentRegions(in: [inner, imports], isCollapsed: collapsed([])).isEmpty)
    }
}

@MainActor
@Suite(.uiGate)
struct FoldCaretRelocatorTests {
    private let hidden = NSRange(location: 10, length: 16)

    @Test
    func aCaretInsideTheHiddenTextMovesToTheStartOfTheHiddenRange() {
        let result = FoldCaretRelocator.relocated([NSRange(location: 15, length: 0)], hiding: [hidden])

        #expect(result == [NSRange(location: 10, length: 0)])
    }

    @Test
    func aSelectionEndingInsideTheHiddenTextCollapsesToo() {
        let result = FoldCaretRelocator.relocated([NSRange(location: 2, length: 14)], hiding: [hidden])

        #expect(result == [NSRange(location: 10, length: 0)])
    }

    @Test
    func positionsOnTheBoundariesStayVisible() {
        let result = FoldCaretRelocator.relocated(
            [NSRange(location: 10, length: 0), NSRange(location: 26, length: 0), NSRange(location: 0, length: 3)],
            hiding: [hidden]
        )

        #expect(result == nil)
    }

    @Test
    func onlyTheAffectedSelectionsChangeAndEveryHiddenRangeIsChecked() {
        let other = NSRange(location: 40, length: 8)
        let selections = [NSRange(location: 1, length: 0), NSRange(location: 44, length: 0), NSRange(location: 12, length: 0)]

        let result = FoldCaretRelocator.relocated(selections, hiding: [hidden, other])

        #expect(result == [NSRange(location: 1, length: 0), NSRange(location: 40, length: 0), NSRange(location: 10, length: 0)])
    }

    @Test
    func noHiddenRangesOrSelectionsChangeNothing() {
        #expect(FoldCaretRelocator.relocated([NSRange(location: 12, length: 0)], hiding: []) == nil)
        #expect(FoldCaretRelocator.relocated([], hiding: [hidden]) == nil)
    }
}

@MainActor
@Suite(.uiGate)
struct FoldSnapshotTests {
    private let index = FoldLineIndex(text: String(repeating: "x\n", count: 12))
    private let region = FoldRegion(startLine: 2, endLine: 6, kind: .block)

    private func hiddenRange() throws -> NSRange {
        try #require(index.hiddenRange(of: region))
    }

    @Test
    func anAttachmentEqualToOrCoveringTheHiddenRangeFoldsTheRegion() throws {
        let hidden = try hiddenRange()

        #expect(FoldAttachmentRelation.foldsRegion(attachment: hidden, hidden: hidden))
        #expect(FoldAttachmentRelation.foldsRegion(
            attachment: NSRange(location: hidden.location - 1, length: hidden.length + 3),
            hidden: hidden
        ))
    }

    @Test
    func anAttachmentCrossingEitherEdgeCountsAsFolded() throws {
        let hidden = try hiddenRange()

        #expect(FoldAttachmentRelation.foldsRegion(
            attachment: NSRange(location: hidden.location - 3, length: 5),
            hidden: hidden
        ))
        #expect(FoldAttachmentRelation.foldsRegion(
            attachment: NSRange(location: hidden.upperBound - 2, length: 5),
            hidden: hidden
        ))
    }

    @Test
    func anAttachmentStrictlyInsideIsAnInnerFoldAndDoesNotFoldTheRegion() throws {
        let hidden = try hiddenRange()

        #expect(!FoldAttachmentRelation.foldsRegion(
            attachment: NSRange(location: hidden.location + 2, length: 3),
            hidden: hidden
        ))
        #expect(!FoldAttachmentRelation.foldsRegion(
            attachment: NSRange(location: hidden.location, length: 3),
            hidden: hidden
        ))
    }

    @Test
    func disjointTouchingAndEmptyAttachmentsDoNotFoldTheRegion() throws {
        let hidden = try hiddenRange()

        #expect(!FoldAttachmentRelation.foldsRegion(attachment: NSRange(location: 0, length: 3), hidden: hidden))
        #expect(!FoldAttachmentRelation.foldsRegion(
            attachment: NSRange(location: hidden.location - 3, length: 3),
            hidden: hidden
        ))
        #expect(!FoldAttachmentRelation.foldsRegion(
            attachment: NSRange(location: hidden.upperBound, length: 3),
            hidden: hidden
        ))
        #expect(!FoldAttachmentRelation.foldsRegion(
            attachment: NSRange(location: hidden.location + 1, length: 0),
            hidden: hidden
        ))
    }

    @Test
    func snapshotQueriesTheAttachmentsAgainstTheRegionsHiddenRange() throws {
        let hidden = try hiddenRange()
        let covered = FoldSnapshot(index: index, attachmentRanges: [hidden])
        let inner = FoldSnapshot(index: index, attachmentRanges: [NSRange(location: hidden.location + 2, length: 3)])
        let invalid = FoldRegion(startLine: 40, endLine: 50, kind: .block)

        #expect(covered.isCollapsed(region))
        #expect(!inner.isCollapsed(region))
        #expect(!covered.isCollapsed(invalid))
        #expect(!FoldSnapshot(index: index, attachmentRanges: []).isCollapsed(region))
    }

    @Test
    func collapsedFoldsMapAttachmentsToLineSpansAndSkipEmptyOnes() throws {
        let hidden = try hiddenRange()
        let snapshot = FoldSnapshot(
            index: index,
            attachmentRanges: [hidden, NSRange(location: 3, length: 0), NSRange(location: 15, length: 4)]
        )

        #expect(snapshot.collapsedFolds == [
            FoldSnapshot.CollapsedFold(region: FoldRegion(startLine: 2, endLine: 6, kind: .block), range: hidden),
            FoldSnapshot.CollapsedFold(region: FoldRegion(startLine: 7, endLine: 9, kind: .block), range: NSRange(location: 15, length: 4))
        ])
    }
}
