import Testing
@testable import Dreamder

@Suite
struct MergeConflictStatusCoverageTests {
    private let nul = "\u{0}"
    private let tail = "N... 100644 100644 100644 100644 h1 h2 h3"

    @Test(arguments: [
        (MergeSideChange.modified, "Modified", false),
        (MergeSideChange.added, "Added", false),
        (MergeSideChange.deleted, "Deleted", true),
        (MergeSideChange.absent, "Absent", true)
    ])
    func everySideChangeHasATitleAndKnowsWhetherItRemovesTheFile(
        change: MergeSideChange,
        title: String,
        isRemoval: Bool
    ) {
        #expect(change.title == title)
        #expect(change.isRemoval == isRemoval)
    }

    @Test
    func entryExposesItsIdentityAndLocation() throws {
        let entry = try #require(MergeConflictStatusParser.parse("u AA \(tail) src/deep/File.swift" + nul).first)

        #expect(entry.id == "src/deep/File.swift")
        #expect(entry.fileName == "File.swift")
        #expect(entry.directory == "src/deep")
        #expect(entry.isBothDeleted == false)
    }

    @Test
    func rootLevelEntryHasNoDirectory() throws {
        let entry = try #require(MergeConflictStatusParser.parse("u UU \(tail) README.md" + nul).first)

        #expect(entry.directory.isEmpty)
        #expect(entry.fileName == "README.md")
    }

    @Test
    func changeForChoiceFollowsTheSwapForEveryCombination() throws {
        let entry = try #require(MergeConflictStatusParser.parse("u AU \(tail) a.txt" + nul).first)

        #expect(entry.change(for: .yours, swapsSides: false) == .added)
        #expect(entry.change(for: .theirs, swapsSides: false) == .absent)
        #expect(entry.change(for: .yours, swapsSides: true) == .absent)
        #expect(entry.change(for: .theirs, swapsSides: true) == .added)
    }

    @Test
    func rejectsRecordsWhoseStatusCodesAreNotTwoCharacters() {
        #expect(MergeConflictStatusParser.parse("u UUU \(tail) a.txt" + nul).isEmpty)
        #expect(MergeConflictStatusParser.parse("u U \(tail) a.txt" + nul).isEmpty)
    }

    @Test
    func rejectsRecordsWithAnEmptyPath() {
        #expect(MergeConflictStatusParser.parse("u UU \(tail) " + nul).isEmpty)
    }

    @Test
    func keepsEveryUnmergedRecordInOutputOrder() {
        let output = ["u UU \(tail) b.txt", "1 .M N... 100644 100644 100644 aaa aaa aaa c.txt", "u DD \(tail) a.txt"]
            .joined(separator: nul) + nul

        let entries = MergeConflictStatusParser.parse(output)

        #expect(entries.map(\.path) == ["b.txt", "a.txt"])
        #expect(entries.map(\.statusCodes) == ["UU", "DD"])
        #expect(entries.last?.isBothDeleted == true)
    }

    @Test
    func unknownStatusCodesDefaultToModifiedOnBothSides() {
        let sides = MergeConflictStatusParser.sideChanges(for: "ZZ")

        #expect(sides.ours == .modified)
        #expect(sides.theirs == .modified)
    }
}
