import Foundation
import Testing
@testable import Dreamder

struct EditorCaretToggleTests {
    @Test
    func newOffsetAddsACaret() {
        let toggled = EditorCaretToggle.toggled([NSRange(location: 2, length: 0)], at: 5)
        #expect(toggled == [NSRange(location: 2, length: 0), NSRange(location: 5, length: 0)])
    }

    @Test
    func existingCaretIsRemovedWhenOthersRemain() {
        let toggled = EditorCaretToggle.toggled(
            [NSRange(location: 2, length: 0), NSRange(location: 5, length: 0)],
            at: 5
        )
        #expect(toggled == [NSRange(location: 2, length: 0)])
    }

    @Test
    func theOnlyCaretStays() {
        let only = [NSRange(location: 5, length: 0)]
        #expect(EditorCaretToggle.toggled(only, at: 5) == only)
    }

    @Test
    func clickInsideASelectionChangesNothing() {
        let selections = [NSRange(location: 2, length: 6)]
        #expect(EditorCaretToggle.toggled(selections, at: 4) == selections)
    }

    @Test
    func clickOnASelectionEdgeAddsACaret() {
        let selections = [NSRange(location: 2, length: 6)]
        #expect(
            EditorCaretToggle.toggled(selections, at: 8)
                == [NSRange(location: 2, length: 6), NSRange(location: 8, length: 0)]
        )
    }
}
