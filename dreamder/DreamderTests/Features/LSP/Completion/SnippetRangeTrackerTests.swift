import Foundation
import Testing
@testable import Dreamder

@Suite("Snippet range tracker")
struct SnippetRangeTrackerTests {
    private func make(_ source: String, origin: Int = 0) -> SnippetRangeTracker {
        SnippetRangeTracker(template: SnippetTemplate(parsing: source), origin: origin)
    }

    private func ranges(_ tracker: SnippetRangeTracker, stop: Int) -> [[Int]] {
        tracker.stops[stop].slots.filter(\.isAlive).map { [$0.range.location, $0.range.length] }
    }

    @Test func buildsStopsInTabOrderEndingWithTheFinalCaret() {
        let tracker = make("${2:b} ${1:a}$0", origin: 10)
        #expect(tracker.stops.map(\.index) == [1, 2, 0])
        #expect(ranges(tracker, stop: 0) == [[12, 1]])
        #expect(ranges(tracker, stop: 1) == [[10, 1]])
        #expect(tracker.finalPosition == 2)
        #expect(tracker.finalCaret == 13)
        #expect(tracker.stops[2].isFinal)
        #expect(!tracker.stops[0].isFinal)
    }

    @Test func navigatesForwardAndBackward() {
        let tracker = make("${1:a} ${2:b} ${3:c}")
        #expect(tracker.firstPosition() == 0)
        #expect(tracker.nextPosition(after: 0) == 1)
        #expect(tracker.nextPosition(after: 1) == 2)
        #expect(tracker.nextPosition(after: 2) == tracker.finalPosition)
        #expect(tracker.previousPosition(before: 0) == nil)
        #expect(tracker.previousPosition(before: 2) == 1)
        #expect(tracker.previousPosition(before: tracker.finalPosition) == 2)
        #expect(tracker.primaryRange(of: 1) == NSRange(location: 2, length: 1))
    }

    @Test func typingInTheActiveStopMovesTheFollowingStops() {
        var tracker = make("${1:a} ${2:b}$0", origin: 10)
        let slot = tracker.slot(containing: NSRange(location: 10, length: 1), in: 0)
        #expect(slot == 0)
        tracker.apply(edit: NSRange(location: 10, length: 1), newLength: 3, stop: 0, slot: 0)
        #expect(ranges(tracker, stop: 0) == [[10, 3]])
        #expect(ranges(tracker, stop: 1) == [[14, 1]])
        #expect(tracker.finalCaret == 15)
    }

    @Test func insertingAtTheEndOfTheActiveStopExtendsIt() {
        var tracker = make("${1:ab} ${2:b}")
        let edit = NSRange(location: 2, length: 0)
        #expect(tracker.slot(containing: edit, in: 0) == 0)
        tracker.apply(edit: edit, newLength: 2, stop: 0, slot: 0)
        #expect(ranges(tracker, stop: 0) == [[0, 4]])
        #expect(ranges(tracker, stop: 1) == [[5, 1]])
    }

    @Test func deletingBeforeLaterStopsShiftsThemLeft() {
        var tracker = make("${1:abc} ${2:d}")
        tracker.apply(edit: NSRange(location: 0, length: 3), newLength: 0, stop: 0, slot: 0)
        #expect(ranges(tracker, stop: 0) == [[0, 0]])
        #expect(ranges(tracker, stop: 1) == [[1, 1]])
    }

    @Test func emptyNeighboursKeepTheirTemplateOrder() {
        var forward = make("$1$2")
        forward.apply(edit: NSRange(location: 0, length: 0), newLength: 1, stop: 0, slot: 0)
        #expect(ranges(forward, stop: 0) == [[0, 1]])
        #expect(ranges(forward, stop: 1) == [[1, 0]])
        #expect(forward.finalCaret == 1)

        var backward = make("$1$2")
        let slot = backward.slot(containing: NSRange(location: 0, length: 0), in: 1)
        #expect(slot == 0)
        backward.apply(edit: NSRange(location: 0, length: 0), newLength: 1, stop: 1, slot: 0)
        #expect(ranges(backward, stop: 0) == [[0, 0]])
        #expect(ranges(backward, stop: 1) == [[0, 1]])
        #expect(backward.finalCaret == 1)
    }

    @Test func aParentStartingWhereItsChildStartsComesBeforeTheChild() {
        var tracker = make("${1:${2:b}c}")
        #expect(ranges(tracker, stop: 0) == [[0, 2]])
        #expect(ranges(tracker, stop: 1) == [[0, 1]])
        #expect(tracker.stops[0].slots[0].order < tracker.stops[1].slots[0].order)
        tracker.apply(edit: NSRange(location: 0, length: 0), newLength: 1, stop: 1, slot: 0)
        #expect(ranges(tracker, stop: 0) == [[0, 3]])
        #expect(ranges(tracker, stop: 1) == [[0, 2]])
    }

    @Test func nestedStopsGrowTheirParents() {
        var tracker = make("${1:a${2:b}c}")
        #expect(ranges(tracker, stop: 0) == [[0, 3]])
        #expect(ranges(tracker, stop: 1) == [[1, 1]])
        tracker.apply(edit: NSRange(location: 1, length: 1), newLength: 2, stop: 1, slot: 0)
        #expect(ranges(tracker, stop: 0) == [[0, 4]])
        #expect(ranges(tracker, stop: 1) == [[1, 2]])
    }

    @Test func mirrorsAreEditedThroughTheirOwnSlot() {
        var tracker = make("${1:x} $1 ${2:y}")
        #expect(ranges(tracker, stop: 0) == [[0, 1], [2, 1]])
        #expect(tracker.mirrorSlots(of: 0, excluding: 0) == [1])
        #expect(tracker.range(of: 0, slot: 1) == NSRange(location: 2, length: 1))
        tracker.apply(edit: NSRange(location: 2, length: 1), newLength: 3, stop: 0, slot: 1)
        #expect(ranges(tracker, stop: 0) == [[0, 1], [2, 3]])
        #expect(ranges(tracker, stop: 1) == [[6, 1]])
    }

    @Test func editsCoveringAStopKillItAndNavigationSkipsIt() {
        var tracker = make("${1:ab}${2:cd}${3:ef}")
        tracker.apply(edit: NSRange(location: 1, length: 2), newLength: 0, stop: 0, slot: 0)
        #expect(!tracker.stops[1].isAlive)
        #expect(tracker.stops[2].isAlive)
        #expect(tracker.nextPosition(after: 0) == 2)
        #expect(tracker.previousPosition(before: 2) == 0)
        #expect(tracker.primaryRange(of: 1) == nil)
    }

    @Test func editsCoveringTheFinalCaretCollapseItInsteadOfKillingIt() {
        var tracker = make("${1:ab}${2:cd}$0")
        #expect(tracker.finalCaret == 4)
        tracker.apply(edit: NSRange(location: 3, length: 2), newLength: 1, stop: 0, slot: 0)
        #expect(tracker.stops[tracker.finalPosition].isAlive)
        #expect(tracker.finalCaret == 4)
    }

    @Test func editsStartingAtTheEndOfAnotherStopLeaveItAlone() {
        var tracker = make("${1:ab}${2:cd}")
        tracker.apply(edit: NSRange(location: 2, length: 1), newLength: 4, stop: 1, slot: 0)
        #expect(ranges(tracker, stop: 0) == [[0, 2]])
        #expect(ranges(tracker, stop: 1) == [[2, 5]])
    }

    @Test func editsInsideAnotherStopGrowIt() {
        var tracker = make("${1:ab} ${2:cdef}")
        tracker.apply(edit: NSRange(location: 4, length: 1), newLength: 3, stop: 0, slot: 0)
        #expect(ranges(tracker, stop: 1) == [[3, 6]])
    }

    @Test func selectionsAreContainedInclusively() {
        let tracker = make("${1:abc} ${2:d}", origin: 5)
        #expect(tracker.contains(selection: NSRange(location: 5, length: 3), in: 0))
        #expect(tracker.contains(selection: NSRange(location: 8, length: 0), in: 0))
        #expect(!tracker.contains(selection: NSRange(location: 9, length: 0), in: 0))
        #expect(!tracker.contains(selection: NSRange(location: 4, length: 0), in: 0))
        #expect(!tracker.contains(selection: NSRange(location: 6, length: 3), in: 0))
    }

    @Test func editsAfterAStopAreIgnoredByIt() {
        var tracker = make("${1:a}${2:b}")
        tracker.apply(edit: NSRange(location: 2, length: 0), newLength: 4, stop: 1, slot: 0)
        #expect(ranges(tracker, stop: 0) == [[0, 1]])
        #expect(ranges(tracker, stop: 1) == [[1, 5]])
    }
}
