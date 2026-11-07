import Testing
import Foundation
@testable import Dreamder

@Suite struct LineMergeComparisonTests {
    typealias Marks = (String, String, String)

    private enum Mode {
        case diff
        case merge
    }

    private func mod(
        _ line1: Int,
        _ line2: Int,
        _ line3: Int,
        _ count1: Int,
        _ count2: Int,
        _ count3: Int
    ) -> MergeRange {
        MergeRange(line1, line1 + count1, line2, line2 + count2, line3, line3 + count3)
    }

    private func lines(
        _ mode: Mode,
        _ left: String,
        _ base: String,
        _ right: String,
        matching: Marks? = nil,
        changes: [MergeRange]? = nil,
        policy: ComparisonPolicy = .default,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let hasExpectation = matching != nil || changes != nil
        #expect(hasExpectation, "matching or changes required", sourceLocation: sourceLocation)

        let leftText = DiffEngineTestSupport.source(left)
        let baseText = DiffEngineTestSupport.source(base)
        let rightText = DiffEngineTestSupport.source(right)

        let ranges: [MergeRange]
        switch mode {
        case .diff:
            ranges = try ComparisonManager.compareLines(leftText, baseText, rightText, policy: policy)
        case .merge:
            ranges = try ComparisonManager.mergeLines(leftText, baseText, rightText, policy: policy)
        }

        if let matching {
            #expect(matching.0.count == leftText.count, "Left marks length, \(mode), policy: \(policy)", sourceLocation: sourceLocation)
            #expect(matching.1.count == baseText.count, "Base marks length, \(mode), policy: \(policy)", sourceLocation: sourceLocation)
            #expect(matching.2.count == rightText.count, "Right marks length, \(mode), policy: \(policy)", sourceLocation: sourceLocation)
            #expect(
                DiffEngineTestSupport.changedOffsets(ranges, side: .left) == DiffEngineTestSupport.matchedLines(matching.0),
                "Left, \(mode), policy: \(policy)",
                sourceLocation: sourceLocation
            )
            #expect(
                DiffEngineTestSupport.changedOffsets(ranges, side: .base) == DiffEngineTestSupport.matchedLines(matching.1),
                "Base, \(mode), policy: \(policy)",
                sourceLocation: sourceLocation
            )
            #expect(
                DiffEngineTestSupport.changedOffsets(ranges, side: .right) == DiffEngineTestSupport.matchedLines(matching.2),
                "Right, \(mode), policy: \(policy)",
                sourceLocation: sourceLocation
            )
        }
        if let changes {
            #expect(ranges == changes, "\(mode), policy: \(policy)", sourceLocation: sourceLocation)
        }
    }

    @Test func simpleCases() throws {
        try lines(.merge, "", "", "", matching: ("", "", ""), changes: [])

        try lines(.merge, "x_y_z", "x_y_z", "x_y_z", matching: (" _ _ ", " _ _ ", " _ _ "), changes: [])

        try lines(.merge, "", "", "x", changes: [mod(0, 0, 0, 1, 1, 1)])

        try lines(.merge, "", "", "_x", matching: ("", "", "_-"), changes: [mod(1, 1, 1, 0, 0, 1)])

        try lines(.merge, "x", "y", "x", matching: ("-", "-", "-"))

        try lines(.merge, "x", "x_y", "x", matching: (" ", " _-", " "))

        try lines(.merge, "x", "y_x", "x", matching: (" ", "-_ ", " "))

        try lines(.merge, "x_y_z", "x_Y_z", "x_y_z", matching: (" _-_ ", " _-_ ", " _-_ "))

        try lines(.merge, "x_y_z", "X_y_Z", "x_y_z", matching: ("-_ _-", "-_ _-", "-_ _-"))
    }

    @Test func ignoreWhitespaces() throws {
        try lines(.diff, "x_ y _z", "x_y_z", "x_  y_  z", changes: [], policy: .ignoreWhitespaces)

        try lines(
            .merge, "x_ y _z", "x_y_z", "x_  y_  z",
            changes: [mod(1, 1, 1, 2, 2, 2)],
            policy: .ignoreWhitespaces
        )

        try lines(
            .diff, "x_ y _z", "x_Y_z", "x_  y_  z",
            changes: [mod(1, 1, 1, 1, 1, 1)],
            policy: .ignoreWhitespaces
        )

        try lines(
            .merge, "x_ y _z", "x_Y_z", "x_  y_  z",
            changes: [mod(1, 1, 1, 1, 1, 1), mod(2, 2, 2, 1, 1, 1)],
            policy: .ignoreWhitespaces
        )

        try lines(
            .merge, "x_ y _z", "x_Y_z", "x_  y_z",
            changes: [mod(1, 1, 1, 1, 1, 1)],
            policy: .ignoreWhitespaces
        )

        try lines(
            .merge, "x_ y _z", "x_y_z", "x_  y_z",
            changes: [mod(1, 1, 1, 1, 1, 1)],
            policy: .ignoreWhitespaces
        )

        try lines(
            .merge, " x _y_z", "x_y_z", "x_y_  z",
            changes: [mod(0, 0, 0, 1, 1, 1), mod(2, 2, 2, 1, 1, 1)],
            policy: .ignoreWhitespaces
        )

        try lines(
            .diff, " x_new_y_z", "x_ y _z", "x_y_new_ z",
            changes: [mod(1, 1, 1, 1, 0, 0), mod(3, 2, 2, 0, 0, 1)],
            policy: .ignoreWhitespaces
        )

        try lines(
            .merge, " x_new_y_z", "x_ y _z", "x_y_new_ z",
            changes: [
                mod(0, 0, 0, 1, 1, 1),
                mod(1, 1, 1, 1, 0, 0),
                mod(2, 1, 1, 1, 1, 1),
                mod(3, 2, 2, 0, 0, 1),
                mod(3, 2, 3, 1, 1, 1)
            ],
            policy: .ignoreWhitespaces
        )

        try lines(
            .diff, " x_new_y1_z", "x_ y _z", "x_y2_new_ z",
            changes: [mod(1, 1, 1, 2, 1, 2)],
            policy: .ignoreWhitespaces
        )

        try lines(
            .merge, " x_new_y1_z", "x_ y _z", "x_y2_new_ z",
            changes: [
                mod(0, 0, 0, 1, 1, 1),
                mod(1, 1, 1, 2, 1, 2),
                mod(3, 2, 3, 1, 1, 1)
            ],
            policy: .ignoreWhitespaces
        )
    }
}

@Suite struct MergeConflictTypeTests {
    private let header = "header line"
    private let footer = "footer line"
    private let removed = "removed line"
    private let original = "original line"
    private let changed = "changed line"
    private let leftChanged = "left changed line"
    private let rightChanged = "right changed line"

    private func mod(
        _ line1: Int,
        _ line2: Int,
        _ line3: Int,
        _ count1: Int,
        _ count2: Int,
        _ count3: Int
    ) -> MergeRange {
        MergeRange(line1, line1 + count1, line2, line2 + count2, line3, line3 + count3)
    }

    private func expectMergeTypes(
        left: [String],
        base: [String],
        right: [String],
        ranges expectedRanges: [MergeRange],
        types expectedTypes: [MergeConflictType],
        policy: ComparisonPolicy = .default,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let ranges = try ComparisonManager.mergeLines(left: left, base: base, right: right, policy: policy)
        #expect(ranges == expectedRanges, "ranges, policy: \(policy)", sourceLocation: sourceLocation)

        let types = ranges.map {
            ComparisonManager.mergeType(range: $0, left: left, base: base, right: right, policy: policy)
        }
        #expect(types == expectedTypes, "types, policy: \(policy)", sourceLocation: sourceLocation)
    }

    @Test func insertedByLeftOnly() throws {
        try expectMergeTypes(
            left: [header, changed, footer],
            base: [header, footer],
            right: [header, footer],
            ranges: [mod(1, 1, 1, 1, 0, 0)],
            types: [MergeConflictType(.inserted, leftChange: true, rightChange: false)]
        )
    }

    @Test func insertedByRightOnly() throws {
        try expectMergeTypes(
            left: [header, footer],
            base: [header, footer],
            right: [header, changed, footer],
            ranges: [mod(1, 1, 1, 0, 0, 1)],
            types: [MergeConflictType(.inserted, leftChange: false, rightChange: true)]
        )
    }

    @Test func insertedByBothSidesIdentically() throws {
        try expectMergeTypes(
            left: [header, changed, footer],
            base: [header, footer],
            right: [header, changed, footer],
            ranges: [mod(1, 1, 1, 1, 0, 1)],
            types: [MergeConflictType(.inserted, leftChange: true, rightChange: true)]
        )
    }

    @Test func insertedByBothSidesDifferentlyIsUnresolvableConflict() throws {
        let type = MergeConflictType(.conflict, leftChange: true, rightChange: true, resolutionStrategy: nil)
        try expectMergeTypes(
            left: [header, leftChanged, footer],
            base: [header, footer],
            right: [header, rightChanged, footer],
            ranges: [mod(1, 1, 1, 1, 0, 1)],
            types: [type]
        )
        #expect(!type.canBeResolved)
    }

    @Test func deletedByLeftOnly() throws {
        try expectMergeTypes(
            left: [header, footer],
            base: [header, removed, footer],
            right: [header, removed, footer],
            ranges: [mod(1, 1, 1, 0, 1, 1)],
            types: [MergeConflictType(.deleted, leftChange: true, rightChange: false)]
        )
    }

    @Test func deletedByRightOnly() throws {
        try expectMergeTypes(
            left: [header, removed, footer],
            base: [header, removed, footer],
            right: [header, footer],
            ranges: [mod(1, 1, 1, 1, 1, 0)],
            types: [MergeConflictType(.deleted, leftChange: false, rightChange: true)]
        )
    }

    @Test func deletedByBothSides() throws {
        try expectMergeTypes(
            left: [header, footer],
            base: [header, removed, footer],
            right: [header, footer],
            ranges: [mod(1, 1, 1, 0, 1, 0)],
            types: [MergeConflictType(.deleted, leftChange: true, rightChange: true)]
        )
    }

    @Test func modifiedByLeftOnly() throws {
        try expectMergeTypes(
            left: [header, changed, footer],
            base: [header, original, footer],
            right: [header, original, footer],
            ranges: [mod(1, 1, 1, 1, 1, 1)],
            types: [MergeConflictType(.modified, leftChange: true, rightChange: false)]
        )
    }

    @Test func modifiedByRightOnly() throws {
        try expectMergeTypes(
            left: [header, original, footer],
            base: [header, original, footer],
            right: [header, changed, footer],
            ranges: [mod(1, 1, 1, 1, 1, 1)],
            types: [MergeConflictType(.modified, leftChange: false, rightChange: true)]
        )
    }

    @Test func modifiedByBothSidesIdentically() throws {
        try expectMergeTypes(
            left: [header, changed, footer],
            base: [header, original, footer],
            right: [header, changed, footer],
            ranges: [mod(1, 1, 1, 1, 1, 1)],
            types: [MergeConflictType(.modified, leftChange: true, rightChange: true)]
        )
    }

    @Test func deletedByLeftModifiedByRightIsUnresolvableConflict() throws {
        let type = MergeConflictType(.conflict, leftChange: true, rightChange: true, resolutionStrategy: nil)
        try expectMergeTypes(
            left: [header, footer],
            base: [header, original, footer],
            right: [header, changed, footer],
            ranges: [mod(1, 1, 1, 0, 1, 1)],
            types: [type]
        )
        #expect(!type.canBeResolved)
    }

    @Test func modifiedByLeftDeletedByRightIsUnresolvableConflict() throws {
        let type = MergeConflictType(.conflict, leftChange: true, rightChange: true, resolutionStrategy: nil)
        try expectMergeTypes(
            left: [header, changed, footer],
            base: [header, original, footer],
            right: [header, footer],
            ranges: [mod(1, 1, 1, 1, 1, 0)],
            types: [type]
        )
        #expect(!type.canBeResolved)
    }

    @Test func nonOverlappingEditsOfOneLineAreResolvableConflict() throws {
        let type = MergeConflictType(.conflict, leftChange: true, rightChange: true, resolutionStrategy: .text)
        try expectMergeTypes(
            left: [header, "alpha delta beta gamma", footer],
            base: [header, "alpha beta gamma", footer],
            right: [header, "alpha beta epsilon gamma", footer],
            ranges: [mod(1, 1, 1, 1, 1, 1)],
            types: [type]
        )
        #expect(type.canBeResolved)
    }

    @Test func competingEditsOfSameWordAreUnresolvableConflict() throws {
        let type = MergeConflictType(.conflict, leftChange: true, rightChange: true, resolutionStrategy: nil)
        try expectMergeTypes(
            left: [header, "alpha LEFT gamma", footer],
            base: [header, "alpha beta gamma", footer],
            right: [header, "alpha RIGHT gamma", footer],
            ranges: [mod(1, 1, 1, 1, 1, 1)],
            types: [type]
        )
        #expect(!type.canBeResolved)
    }

    @Test func separateChangesOnEachSideProduceTwoRanges() throws {
        let middle = "middle line"
        let first = "first line"
        let last = "last line"
        try expectMergeTypes(
            left: [header, leftChanged, middle, last, footer],
            base: [header, first, middle, last, footer],
            right: [header, first, middle, rightChanged, footer],
            ranges: [mod(1, 1, 1, 1, 1, 1), mod(3, 3, 3, 1, 1, 1)],
            types: [
                MergeConflictType(.modified, leftChange: true, rightChange: false),
                MergeConflictType(.modified, leftChange: false, rightChange: true)
            ]
        )
    }

    @Test func whitespaceOnlyEditsUnderIgnoreWhitespacesAreModifiedOnTheEditedSide() throws {
        try expectMergeTypes(
            left: [" x ", "y", "z"],
            base: ["x", "y", "z"],
            right: ["x", "y", "  z"],
            ranges: [mod(0, 0, 0, 1, 1, 1), mod(2, 2, 2, 1, 1, 1)],
            types: [
                MergeConflictType(.modified, leftChange: true, rightChange: false),
                MergeConflictType(.modified, leftChange: false, rightChange: true)
            ],
            policy: .ignoreWhitespaces
        )
    }

    @Test func whitespaceOnlyEditsOnBothSidesUnderIgnoreWhitespacesAreModifiedOnBothSides() throws {
        try expectMergeTypes(
            left: ["x", " y ", "z"],
            base: ["x", "y", "z"],
            right: ["x", "  y", "z"],
            ranges: [mod(1, 1, 1, 1, 1, 1)],
            types: [MergeConflictType(.modified, leftChange: true, rightChange: true)],
            policy: .ignoreWhitespaces
        )
    }
}
