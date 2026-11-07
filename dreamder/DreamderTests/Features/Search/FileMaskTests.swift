import Testing
@testable import Dreamder

@Suite
struct FileMaskTests {
    @Test
    func includeAndExcludeMasksFollowIntelliJFileMaskCondition() throws {
        let mask = try FileMask(filter: "*.java, *.js, !Foo.java, !*.min.js")
        #expect(mask.accepts("Bar.java"))
        #expect(!mask.accepts("Bar.javac"))
        #expect(!mask.accepts("Foo.java"))
        #expect(!mask.accepts("Foo.jav"))
        #expect(!mask.accepts("Foo.min.js"))
        #expect(mask.accepts("Foo.js"))
    }

    @Test
    func onlyExclusionsAcceptEverythingElse() throws {
        let mask = try FileMask(filter: "!Foo.java")
        #expect(mask.accepts("Bar.java"))
        #expect(!mask.accepts("Foo.java"))
        #expect(mask.accepts("Foo.js"))
        #expect(mask.accepts("makefile"))
    }

    @Test
    func emptyOrMissingFilterAcceptsEverything() throws {
        for filter in [nil, ""] as [String?] {
            let mask = try FileMask(filter: filter)
            #expect(mask.accepts("anything.at.all"))
            #expect(mask.accepts(""))
        }
    }

    @Test
    func matchingIsCaseInsensitiveAndAnchoredToTheWholeName() throws {
        let mask = try FileMask(filter: "*.SWIFT")
        #expect(mask.accepts("main.swift"))
        #expect(mask.accepts("Main.Swift"))
        #expect(!mask.accepts("main.swift.bak"))
        #expect(!mask.accepts("xmain.swiftx"))
    }

    @Test
    func questionMarkMatchesExactlyOneCharacter() throws {
        let mask = try FileMask(filter: "file?.txt")
        #expect(mask.accepts("file1.txt"))
        #expect(!mask.accepts("file.txt"))
        #expect(!mask.accepts("file12.txt"))
    }

    @Test
    func regexMetacharactersInMasksAreLiteral() throws {
        let mask = try FileMask(filter: "a+b(1)[x]{y}$^|.txt")
        #expect(mask.accepts("a+b(1)[x]{y}$^|.txt"))
        #expect(!mask.accepts("aab(1)[x]{y}$^|.txt"))
        #expect(!mask.accepts("a+b(1)[x]{y}$^|atxt"))
    }

    @Test
    func emptySegmentsAndSurroundingWhitespaceAreIgnored() throws {
        let mask = try FileMask(filter: " *.kt ,, *.kts ")
        #expect(mask.accepts("Build.kt"))
        #expect(mask.accepts("build.gradle.kts"))
        #expect(!mask.accepts("Build.java"))
    }

    @Test
    func convertToRegexEscapesLikeIntelliJPatternUtil() {
        #expect(FileMask.convertToRegex("*.java") == ".*\\.java")
        #expect(FileMask.convertToRegex("a?c") == "a.c")
        #expect(FileMask.convertToRegex("(x)") == "\\(x\\)")
        #expect(FileMask.convertToRegex("a\\b") == "a\\\\b")
        #expect(FileMask.convertToRegex("a/b") == "a\\/b")
        #expect(FileMask.convertToRegex("").isEmpty)
    }
}
