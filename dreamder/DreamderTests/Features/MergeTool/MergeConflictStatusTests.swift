import Testing
@testable import Dreamder

@Suite
struct MergeConflictStatusTests {
    private let nul = "\u{0}"

    @Test
    func parsesUnmergedRecordsOnly() {
        let output = [
            "1 .M N... 100644 100644 100644 aaa aaa aaa Sources/File.swift",
            "u UU N... 100644 100644 100644 100644 h1 h2 h3 Sources/Conflicted.swift",
            "? Untracked.txt"
        ].joined(separator: nul) + nul

        let entries = MergeConflictStatusParser.parse(output)
        #expect(entries.count == 1)
        #expect(entries.first?.path == "Sources/Conflicted.swift")
        #expect(entries.first?.statusCodes == "UU")
        #expect(entries.first?.ours == .modified)
        #expect(entries.first?.theirs == .modified)
    }

    @Test
    func keepsSpacesInPath() {
        let record = "u UU N... 100644 100644 100644 100644 h1 h2 h3 docs/My File.md"
        let entries = MergeConflictStatusParser.parse(record + nul)
        #expect(entries.first?.path == "docs/My File.md")
        #expect(entries.first?.fileName == "My File.md")
        #expect(entries.first?.directory == "docs")
    }

    @Test
    func mapsEveryConflictCode() {
        let cases: [(String, MergeSideChange, MergeSideChange)] = [
            ("DD", .deleted, .deleted),
            ("AU", .added, .absent),
            ("UD", .modified, .deleted),
            ("UA", .absent, .added),
            ("DU", .deleted, .modified),
            ("AA", .added, .added),
            ("UU", .modified, .modified)
        ]
        for (code, ours, theirs) in cases {
            let sides = MergeConflictStatusParser.sideChanges(for: code)
            #expect(sides.ours == ours)
            #expect(sides.theirs == theirs)
        }
    }

    @Test
    func buildsEntryFromRecord() {
        let record = "u DU N... 100644 100644 100644 100644 h1 h2 h3 Removed.swift"
        let entry = MergeConflictStatusParser.parse(record + nul).first
        #expect(entry?.ours == .deleted)
        #expect(entry?.theirs == .modified)
        #expect(entry?.statusCodes == "DU")
        #expect(entry?.isBothDeleted == false)
    }

    @Test
    func bothDeletedEntryIsFlagged() {
        let record = "u DD N... 100644 100644 100644 100644 h1 h2 h3 Gone.swift"
        let entry = MergeConflictStatusParser.parse(record + nul).first
        #expect(entry?.isBothDeleted == true)
    }

    @Test
    func swapsSidesForRebase() throws {
        let entry = try #require(MergeConflictStatusParser.parse(
            "u UU N... 100644 100644 100644 100644 h1 h2 h3 a.txt" + nul
        ).first)

        #expect(entry.change(for: .yours, swapsSides: false) == .modified)
        #expect(entry.change(for: .theirs, swapsSides: false) == .modified)

        let deletion = try #require(MergeConflictStatusParser.parse(
            "u UD N... 100644 100644 100644 100644 h1 h2 h3 a.txt" + nul
        ).first)
        #expect(deletion.change(for: .yours, swapsSides: false) == .modified)
        #expect(deletion.change(for: .theirs, swapsSides: false) == .deleted)
        #expect(deletion.change(for: .yours, swapsSides: true) == .deleted)
        #expect(deletion.change(for: .theirs, swapsSides: true) == .modified)
    }

    @Test
    func ignoresMalformedRecords() {
        #expect(MergeConflictStatusParser.parse("").isEmpty)
        #expect(MergeConflictStatusParser.parse("u UU" + nul).isEmpty)
        #expect(MergeConflictStatusParser.parse("garbage" + nul).isEmpty)
    }
}
