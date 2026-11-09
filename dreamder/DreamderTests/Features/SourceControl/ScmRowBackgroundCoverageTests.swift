import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct ScmRowBackgroundCoverageTests {
    @Test
    func commitRowsHighlightOnlyWhileHovered() {
        #expect(CommitRowBackground.color(isHovering: true) == Islands.hover)
        #expect(CommitRowBackground.color(isHovering: false) == Color.clear)
    }

    @Test
    func diffFileRowsPreferSelectionOverHover() {
        #expect(DiffFileListRow.background(isSelected: true, isHovering: true) == Islands.selection)
        #expect(DiffFileListRow.background(isSelected: true, isHovering: false) == Islands.selection)
        #expect(DiffFileListRow.background(isSelected: false, isHovering: true) == Islands.hover)
        #expect(DiffFileListRow.background(isSelected: false, isHovering: false) == Color.clear)
    }

    @Test
    func conflictRowsPreferSelectionOverHover() {
        #expect(MergeConflictRowView.background(isSelected: true, isHovering: true) == Islands.selection)
        #expect(MergeConflictRowView.background(isSelected: false, isHovering: true) == Islands.hover)
        #expect(MergeConflictRowView.background(isSelected: false, isHovering: false) == Color.clear)
    }
}
