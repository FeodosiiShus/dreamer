import Foundation
import Testing
@testable import Dreamder

struct ExpectedConsoleLink: Sendable {
    let text: String
    let path: String
    let line: Int
    let column: Int?
}

struct ConsoleLinkExample: Sendable, CustomTestStringConvertible {
    let line: String
    let links: [ExpectedConsoleLink]

    var testDescription: String { line }
}

private func example(
    _ line: String,
    _ text: String,
    path: String,
    line number: Int,
    column: Int? = nil
) -> ConsoleLinkExample {
    ConsoleLinkExample(
        line: line,
        links: [ExpectedConsoleLink(text: text, path: path, line: number, column: column)]
    )
}

private let positiveExamples: [ConsoleLinkExample] = [
    example(
        "/abs/File.swift:12:5: error: x",
        "/abs/File.swift:12:5",
        path: "/abs/File.swift",
        line: 12,
        column: 5
    ),
    example("./rel/a.ts:3", "./rel/a.ts:3", path: "./rel/a.ts", line: 3),
    example("src/main.rs:12:5", "src/main.rs:12:5", path: "src/main.rs", line: 12, column: 5),
    example(" --> src/main.rs:12:5", "src/main.rs:12:5", path: "src/main.rs", line: 12, column: 5),
    example("main.go:12:3:", "main.go:12:3", path: "main.go", line: 12, column: 3),
    example("\t/abs/main.go:12 +0x1d", "/abs/main.go:12", path: "/abs/main.go", line: 12),
    example(
        "src/app.ts(12,5): error TS2322: bad",
        "src/app.ts(12,5)",
        path: "src/app.ts",
        line: 12,
        column: 5
    ),
    example("file.cs(12): warning CS0168", "file.cs(12)", path: "file.cs", line: 12),
    example("    at fn (/abs/x.js:12:5)", "/abs/x.js:12:5", path: "/abs/x.js", line: 12, column: 5),
    example(
        "    at async /abs/y.js:7:1",
        "/abs/y.js:7:1",
        path: "/abs/y.js",
        line: 7,
        column: 1
    ),
    example("    at file:///abs/x.js:12:5", "file:///abs/x.js:12:5", path: "/abs/x.js", line: 12, column: 5),
    example(
        "at file:///abs/my%20dir/x.js:3",
        "file:///abs/my%20dir/x.js:3",
        path: "/abs/my dir/x.js",
        line: 3
    ),
    example(
        "at file:///abs/bad%zz.js:3",
        "file:///abs/bad%zz.js:3",
        path: "/abs/bad%zz.js",
        line: 3
    ),
    example(
        "  File \"/abs/x.py\", line 12, in <module>",
        "\"/abs/x.py\", line 12",
        path: "/abs/x.py",
        line: 12
    ),
    example(
        "File \"/abs/my dir/x.py\", line 7",
        "\"/abs/my dir/x.py\", line 7",
        path: "/abs/my dir/x.py",
        line: 7
    ),
    example("File \"x.py\", line 3", "\"x.py\", line 3", path: "x.py", line: 3),
    example(
        "  File \"<stdin>\", line 1, in <module>",
        "\"<stdin>\", line 1",
        path: "<stdin>",
        line: 1
    ),
    example(
        "File \"/a.py:12\", line 3",
        "\"/a.py:12\", line 3",
        path: "/a.py:12",
        line: 3
    ),
    example("~/proj/a.rs:3:1", "~/proj/a.rs:3:1", path: "~/proj/a.rs", line: 3, column: 1),
    example("[src/a.ts:3]", "src/a.ts:3", path: "src/a.ts", line: 3),
    example("(src/a.ts:3)", "src/a.ts:3", path: "src/a.ts", line: 3),
    example("\"src/a.ts:3\"", "src/a.ts:3", path: "src/a.ts", line: 3),
    example("'src/a.ts:3'", "src/a.ts:3", path: "src/a.ts", line: 3),
    example("see src/a.ts:3.", "src/a.ts:3", path: "src/a.ts", line: 3),
    example("see src/a.ts:3, then", "src/a.ts:3", path: "src/a.ts", line: 3),
    example("see src/a.ts:3;", "src/a.ts:3", path: "src/a.ts", line: 3),
    example("{src/a.ts:3}!", "src/a.ts:3", path: "src/a.ts", line: 3),
    example("`src/a.ts:3`", "src/a.ts:3", path: "src/a.ts", line: 3),
    example("<src/a.ts:3>", "src/a.ts:3", path: "src/a.ts", line: 3),
    example("a|src/a.ts:3", "src/a.ts:3", path: "src/a.ts", line: 3),
    example(".gitignore:3", ".gitignore:3", path: ".gitignore", line: 3),
    example("a.c:3:0", "a.c:3:0", path: "a.c", line: 3, column: 0),
    example("a.rs:999999999", "a.rs:999999999", path: "a.rs", line: 999_999_999),
    example("/дом/файл.rs:4", "/дом/файл.rs:4", path: "/дом/файл.rs", line: 4),
    example("🙂 src/a.rs:3:2", "src/a.rs:3:2", path: "src/a.rs", line: 3, column: 2),
    example("dir/2x/v1.2.3.tar:5", "dir/2x/v1.2.3.tar:5", path: "dir/2x/v1.2.3.tar", line: 5),
    example("Foo.m3u8:2", "Foo.m3u8:2", path: "Foo.m3u8", line: 2),
    example("a/b:3", "a/b:3", path: "a/b", line: 3),
    ConsoleLinkExample(
        line: "a.swift:1:2 b.swift:3 → c(d).ts(4,5)",
        links: [
            ExpectedConsoleLink(text: "a.swift:1:2", path: "a.swift", line: 1, column: 2),
            ExpectedConsoleLink(text: "b.swift:3", path: "b.swift", line: 3, column: nil),
            ExpectedConsoleLink(text: "c(d).ts(4,5)", path: "c(d).ts", line: 4, column: 5)
        ]
    ),
    ConsoleLinkExample(
        line: "error: /abs/a.swift:3:1: note in File \"/abs/b.py\", line 9 and ./c.ts:1",
        links: [
            ExpectedConsoleLink(text: "/abs/a.swift:3:1", path: "/abs/a.swift", line: 3, column: 1),
            ExpectedConsoleLink(text: "\"/abs/b.py\", line 9", path: "/abs/b.py", line: 9, column: nil),
            ExpectedConsoleLink(text: "./c.ts:1", path: "./c.ts", line: 1, column: nil)
        ]
    )
]

private let negativeLines: [String] = [
    "",
    "   ",
    "http://host:8080/x.js:12",
    "https://example.com/a.js:3:4",
    "12:30:45",
    "3:4 ratio",
    "version 1.2:3",
    "localhost:3000",
    "key:value",
    "src/main.rs",
    "src/main.rs: error",
    "file.123:4",
    "a.rs:0",
    "a.rs:0:5",
    "a.rs:1234567890",
    "a.rs:3:1234567890",
    "foo.ts(0)",
    "foo.ts()",
    "foo.ts(1,2,3)",
    "foo.ts(1,)",
    "foo.ts(a)",
    "foo.ts(1,x)",
    ":12",
    "/abs/dir/:3",
    "(12)",
    "file://:3",
    "File \"x.py\", line 0",
    "File \"\", line 3",
    "File \"x.py\" line 3",
    "File \"x.py\", line",
    "File \"x.py\", line 1234567890",
    "File \"abc",
    "File ",
    "File x.py, line 3",
    "xFile \"a.py\", line 3",
    "Fil",
    "a.\u{0}:3",
    "a.:3"
]

struct ConsoleFileLinkDetectorTests {
    private let detector = ConsoleFileLinkDetector()

    private func range(of text: String, in line: String) throws -> Range<Int> {
        let found = try #require(line.range(of: text))
        let lower = line.distance(from: line.startIndex, to: found.lowerBound)
        return lower..<(lower + text.count)
    }

    @Test(arguments: positiveExamples)
    func positivesProduceExactRangesPathsAndPositions(_ example: ConsoleLinkExample) throws {
        let expected = try example.links.map {
            ConsoleFileLink(
                range: try range(of: $0.text, in: example.line),
                path: $0.path,
                line: $0.line,
                column: $0.column
            )
        }

        #expect(detector.links(in: example.line) == expected)
        #expect(detector.links(inCharacters: Array(example.line)) == expected)
    }

    @Test(arguments: negativeLines)
    func negativesProduceNoLinks(_ line: String) {
        #expect(detector.links(in: line).isEmpty)
    }

    @Test
    func linesLongerThanTheLimitHaveNoLinks() {
        let limit = ConsoleFileLinkDetector.maximumLineLength
        let link = "src/a.rs:3"
        let atLimit = link + String(repeating: " ", count: limit - link.count)
        let overLimit = atLimit + " "

        #expect(atLimit.count == limit)
        #expect(detector.links(in: atLimit).count == 1)
        #expect(detector.links(in: overLimit).isEmpty)
        #expect(detector.links(in: String(repeating: "a", count: limit + 1) + " src/a.rs:3").isEmpty)
    }

    @Test
    func linksAreOrderedAndNeverOverlap() {
        let line = "z.rs:1 a.rs:2 File \"/m.py\", line 3 y.rs:4"
        let links = detector.links(in: line)

        #expect(links.map(\.path) == ["z.rs", "a.rs", "/m.py", "y.rs"])
        for (previous, next) in zip(links, links.dropFirst()) {
            #expect(previous.range.upperBound <= next.range.lowerBound)
        }
    }

    @Test
    func quotedPythonPathsWinOverEmbeddedColonSuffixes() {
        let links = detector.links(in: "File \"/a.py:12\", line 3")

        #expect(links.count == 1)
        #expect(links.first?.line == 3)
        #expect(links.first?.column == nil)
    }
}
