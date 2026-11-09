import Foundation
import Testing
@testable import Dreamder

@Suite
struct RecentLocationsRowsTests {
    private static let tenLines = (1...10).map { "l\($0)" }.joined(separator: "\n")

    private func numbers(_ preview: RecentLocationsPreview) -> [Int] {
        guard case .lines(let lines) = preview else { return [] }
        return lines.map(\.number)
    }

    private func texts(_ preview: RecentLocationsPreview) -> [String] {
        guard case .lines(let lines) = preview else { return [] }
        return lines.map(\.text)
    }

    private func preview(_ text: String, caretLine: Int) -> RecentLocationsPreview {
        RecentLocationsMapping.preview(lines: LSPUsagesMapping.lineUnits(in: text), caretLine: caretLine)
    }

    @Test(
        "RecentLocationsDataModel.getLinesRange keeps a window of lines before and after the place",
        arguments: [
            (1, [1, 2, 3, 4, 5]),
            (2, [1, 2, 3, 4, 5]),
            (3, [1, 2, 3, 4, 5]),
            (4, [2, 3, 4, 5, 6]),
            (5, [3, 4, 5, 6, 7]),
            (8, [6, 7, 8, 9, 10]),
            (9, [7, 8, 9, 10]),
            (10, [7, 8, 9, 10])
        ]
    )
    func windowAroundThePlace(caretLine: Int, expected: [Int]) {
        #expect(numbers(preview(Self.tenLines, caretLine: caretLine)) == expected)
    }

    @Test
    func windowIsClampedToShortFiles() {
        #expect(numbers(preview("a\nb\nc", caretLine: 2)) == [1, 2, 3])
        #expect(numbers(preview("only", caretLine: 1)) == [1])
    }

    @Test
    func caretLineIsMarked() {
        guard case .lines(let lines) = preview(Self.tenLines, caretLine: 5) else {
            Issue.record("expected lines")
            return
        }

        #expect(lines.filter(\.isCaretLine).map(\.number) == [5])
        #expect(lines.map(\.text) == ["l3", "l4", "l5", "l6", "l7"])
    }

    @Test
    func staleLineNumbersAreClamped() {
        #expect(numbers(preview("a\nb\nc", caretLine: 99)) == [1, 2, 3])
        #expect(numbers(preview(Self.tenLines, caretLine: 0)) == [1, 2, 3, 4, 5])
        #expect(numbers(preview(Self.tenLines, caretLine: -4)) == [1, 2, 3, 4, 5])
    }

    @Test
    func blankLinesAtBothEndsAreTrimmed() {
        let result = preview("\n\nfoo\nbar\n\n", caretLine: 3)

        #expect(numbers(result) == [3, 4])
        #expect(texts(result) == ["foo", "bar"])
    }

    @Test
    func whitespaceOnlyLinesAtTheEndsAreTrimmedToo() {
        let result = preview("  \n\t\nfoo\n   \n", caretLine: 3)

        #expect(numbers(result) == [3])
    }

    @Test
    func blankLinesBetweenCodeAreKept() {
        let result = preview("a\n\nb", caretLine: 2)

        #expect(numbers(result) == [1, 2, 3])
    }

    @Test
    func aWindowOfOnlyBlankLinesCollapsesToItsFirstLine() {
        let result = preview("   \n\n\t\n", caretLine: 2)

        #expect(numbers(result) == [1])
        #expect(texts(result) == ["   "])
    }

    @Test
    func emptyFilesShowTheEmptyLinesText() {
        #expect(preview("", caretLine: 1) == .emptyFile)
        #expect(preview("\n", caretLine: 1) == .emptyFile)
        #expect(RecentLocationsMapping.preview(lines: [], caretLine: 1) == .emptyFile)
    }

    @Test
    func lineEndingsAreNotPartOfTheText() {
        #expect(texts(preview("a\r\nb\r\nc", caretLine: 2)) == ["a", "b", "c"])
    }

    @Test
    func longLinesAreCutAtOneThousandCharacters() {
        let long = String(repeating: "x", count: 1_500)

        let result = preview("short\n\(long)", caretLine: 2)

        #expect(texts(result) == ["short", String(repeating: "x", count: RecentLocationsMapping.maxLineLength)])
        #expect(RecentLocationsMapping.maxLineLength == 1_000)
        #expect(RecentLocationsMapping.linesBeforeAndAfter == 2)
    }

    @Test
    func rowsCarryNameIconDirectoryAndPreview() {
        let places = [
            EditorPlace(fileURL: URL(filePath: "/work/app/Sources/Main.swift"), line: 7, column: 3),
            EditorPlace(fileURL: URL(filePath: "/work/app/README.md"), line: 1, column: 1)
        ]
        let texts: [URL: String] = [
            URL(filePath: "/work/app/Sources/Main.swift"): Self.tenLines,
            URL(filePath: "/work/app/README.md"): ""
        ]

        let rows = RecentLocationsMapping.rows(places: places, texts: texts, workspacePath: "/work/app")

        #expect(rows.map(\.fileName) == ["Main.swift", "README.md"])
        #expect(rows.map(\.title) == ["Main.swift:7", "README.md:1"])
        #expect(rows.map(\.relativeDirectory) == ["Sources", ""])
        #expect(rows[0].fileIconName == "fileTypes/swiftLang")
        #expect(rows[0].fileIconName == IntelliJIcon.fileIcon(for: "Main.swift"))
        #expect(numbers(rows[0].preview) == [5, 6, 7, 8, 9])
        #expect(rows[1].preview == .emptyFile)
    }

    @Test
    func rowsWithoutTextArePending() {
        let place = EditorPlace(fileURL: URL(filePath: "/work/app/Main.swift"), line: 7, column: 3)

        let rows = RecentLocationsMapping.rows(places: [place], texts: [:], workspacePath: nil)

        #expect(rows.map(\.preview) == [.pending])
    }

    @Test
    func placesOfTheSameFileShareOneTextAndKeepTheirOwnWindow() {
        let url = URL(filePath: "/work/app/Main.swift")
        let places = [
            EditorPlace(fileURL: url, line: 2, column: 1),
            EditorPlace(fileURL: url, line: 9, column: 1)
        ]

        let rows = RecentLocationsMapping.rows(places: places, texts: [url: Self.tenLines], workspacePath: "/work/app")

        #expect(rows.map { numbers($0.preview) } == [[1, 2, 3, 4, 5], [7, 8, 9, 10]])
    }

    @Test
    func rowIdentifiersAreStableAndDistinguishPlaces() {
        let url = URL(filePath: "/work/app/Main.swift")
        let single = EditorPlace(fileURL: url, line: 7, column: 3)
        let twoCarets = EditorPlace(fileURL: url, carets: [.init(line: 7, column: 3), .init(line: 9, column: 1)])

        let rows = RecentLocationsMapping.rows(places: [single, twoCarets], texts: [:], workspacePath: nil)

        #expect(rows[0].id == "/work/app/Main.swift#7:3")
        #expect(rows[1].id == "/work/app/Main.swift#7:3,9:1")
        #expect(rows[0].id != rows[1].id)
    }
}
