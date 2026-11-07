import Testing
@testable import Dreamder

@Suite
struct GitLineChangeTests {
    @Test
    func mapsInsertionToAddedMarker() throws {
        let change = try #require(GitLineChange(hunk: .init(oldStart: 0, oldCount: 0, newStart: 1, newCount: 3)))
        #expect(change.kind == .added)
        #expect(change.newLines == 1...3)
        #expect(change.oldLines == nil)
        #expect(change.anchorLine == 1)
    }

    @Test
    func mapsDeletionToBoundaryMarker() throws {
        let change = try #require(GitLineChange(hunk: .init(oldStart: 6, oldCount: 2, newStart: 5, newCount: 0)))
        #expect(change.kind == .deleted)
        #expect(change.newLines == nil)
        #expect(change.oldLines == 6...7)
        #expect(change.anchorLine == 5)
    }

    @Test
    func mapsDeletionAtStartOfFile() throws {
        let change = try #require(GitLineChange(hunk: .init(oldStart: 1, oldCount: 1, newStart: 0, newCount: 0)))
        #expect(change.kind == .deleted)
        #expect(change.anchorLine == 0)
    }

    @Test
    func mapsReplacementToModifiedMarker() throws {
        let change = try #require(GitLineChange(hunk: .init(oldStart: 5, oldCount: 2, newStart: 5, newCount: 4)))
        #expect(change.kind == .modified)
        #expect(change.newLines == 5...8)
        #expect(change.oldLines == 5...6)
        #expect(change.anchorLine == 5)
    }

    @Test
    func ignoresEmptyHunk() {
        #expect(GitLineChange(hunk: .init(oldStart: 0, oldCount: 0, newStart: 0, newCount: 0)) == nil)
    }

    @Test
    func ignoresInvalidStarts() {
        #expect(GitLineChange(hunk: .init(oldStart: 0, oldCount: 1, newStart: 0, newCount: 0)) == nil)
        #expect(GitLineChange(hunk: .init(oldStart: 0, oldCount: 0, newStart: 0, newCount: 1)) == nil)
    }

    @Test
    func buildsMarkersFromDiffOutput() throws {
        let output = """
        diff --git a/f.txt b/f.txt
        --- a/f.txt
        +++ b/f.txt
        @@ -1,2 +1,2 @@
        -one
        -two
        +ONE
        +TWO
        @@ -10,0 +10,2 @@
        +ten
        +eleven
        @@ -20 +21,0 @@
        -twenty
        """
        let markers = GitLineChange.markers(inDiff: output)
        try #require(markers.count == 3)
        #expect(markers[0].kind == .modified)
        #expect(markers[0].newLines == 1...2)
        #expect(markers[0].oldLines == 1...2)
        #expect(markers[1].kind == .added)
        #expect(markers[1].newLines == 10...11)
        #expect(markers[2].kind == .deleted)
        #expect(markers[2].anchorLine == 21)
        #expect(markers[2].oldLines == 20...20)
    }

    @Test
    func buildsMarkersFromInMemoryDiff() throws {
        let diff = TextDiff(left: "a\nb\nc", right: "a\nB\nc\nd")
        let markers = GitLineChange.markers(from: diff)
        try #require(markers.count == 2)
        #expect(markers[0].kind == .modified)
        #expect(markers[0].newLines == 2...2)
        #expect(markers[0].oldLines == 2...2)
        #expect(markers[1].kind == .added)
        #expect(markers[1].newLines == 4...4)
    }

    @Test
    func buildsMarkersForDeletionFromInMemoryDiff() throws {
        let diff = TextDiff(left: "a\nb\nc\nd", right: "a\nd")
        let markers = GitLineChange.markers(from: diff)
        #expect(markers.count == 1)
        let marker = try #require(markers.first)
        #expect(marker.kind == .deleted)
        #expect(marker.anchorLine == 1)
        #expect(marker.oldLines == 2...3)
    }

    @Test
    func marksWholeUntrackedFileAsAdded() {
        let markers = GitLineChange.wholeFileAdded(lineCount: 4)
        #expect(markers == [GitLineChange(kind: .added, oldLines: nil, newLines: 1...4, anchorLine: 1)])
        #expect(GitLineChange.wholeFileAdded(lineCount: 0).isEmpty)
    }

    @Test
    func identicalTextProducesNoMarkers() {
        #expect(GitLineChange.markers(from: TextDiff(left: "a\nb\n", right: "a\nb\n")).isEmpty)
    }
}
