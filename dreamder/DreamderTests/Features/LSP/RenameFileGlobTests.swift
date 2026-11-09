import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

struct RenameGlobCase: Sendable, CustomTestStringConvertible {
    let glob: String
    let path: String
    let expected: Bool
    var ignoreCase = false

    var testDescription: String {
        "\(glob) on \(path) -> \(expected)"
    }
}

let renameGlobCases: [RenameGlobCase] = [
    RenameGlobCase(glob: "**/*.ts", path: "/a/b/c.ts", expected: true),
    RenameGlobCase(glob: "**/*.ts", path: "/a/b/c.js", expected: false),
    RenameGlobCase(glob: "**/*.ts", path: "c.ts", expected: true),
    RenameGlobCase(glob: "*.ts", path: "c.ts", expected: true),
    RenameGlobCase(glob: "*.ts", path: ".ts", expected: true),
    RenameGlobCase(glob: "*.ts", path: "a/c.ts", expected: false),
    RenameGlobCase(glob: "?.ts", path: "a.ts", expected: true),
    RenameGlobCase(glob: "?.ts", path: "ab.ts", expected: false),
    RenameGlobCase(glob: "?.ts", path: "/.ts", expected: false),
    RenameGlobCase(glob: "src/**", path: "src/a/b", expected: true),
    RenameGlobCase(glob: "src/**", path: "src/", expected: true),
    RenameGlobCase(glob: "src/**", path: "src", expected: false),
    RenameGlobCase(glob: "src/**", path: "other/a", expected: false),
    RenameGlobCase(glob: "src/**/test", path: "src/test", expected: true),
    RenameGlobCase(glob: "src/**/test", path: "src/a/b/test", expected: true),
    RenameGlobCase(glob: "src/**/test", path: "src/a/b/tests", expected: false),
    RenameGlobCase(glob: "**", path: "/any/thing", expected: true),
    RenameGlobCase(glob: "**", path: "", expected: true),
    RenameGlobCase(glob: "***", path: "abc", expected: true),
    RenameGlobCase(glob: "a**b", path: "axxb", expected: true),
    RenameGlobCase(glob: "a**b", path: "a/x/b", expected: true),
    RenameGlobCase(glob: "**/*.{ts,tsx}", path: "/p/a.tsx", expected: true),
    RenameGlobCase(glob: "**/*.{ts,tsx}", path: "/p/a.ts", expected: true),
    RenameGlobCase(glob: "**/*.{ts,tsx}", path: "/p/a.js", expected: false),
    RenameGlobCase(glob: "{a,{b,c}}.txt", path: "b.txt", expected: true),
    RenameGlobCase(glob: "{a,{b,c}}.txt", path: "c.txt", expected: true),
    RenameGlobCase(glob: "{a,{b,c}}.txt", path: "d.txt", expected: false),
    RenameGlobCase(glob: "{a,b", path: "a", expected: false),
    RenameGlobCase(glob: "a}", path: "a}", expected: true),
    RenameGlobCase(glob: "a,b", path: "a,b", expected: true),
    RenameGlobCase(glob: "example.[0-9]", path: "example.5", expected: true),
    RenameGlobCase(glob: "example.[0-9]", path: "example.a", expected: false),
    RenameGlobCase(glob: "example.[!0-9]", path: "example.a", expected: true),
    RenameGlobCase(glob: "example.[!0-9]", path: "example.5", expected: false),
    RenameGlobCase(glob: "a[!x]b", path: "a/b", expected: false),
    RenameGlobCase(glob: "[abc", path: "[abc", expected: true),
    RenameGlobCase(glob: "a[]", path: "a[]", expected: true),
    RenameGlobCase(glob: "[z-a]", path: "a", expected: false),
    RenameGlobCase(glob: "[a\\]", path: "\\", expected: true),
    RenameGlobCase(glob: "[a^b]", path: "^", expected: true),
    RenameGlobCase(glob: "[a&&b]", path: "&", expected: true),
    RenameGlobCase(glob: "[[]", path: "[", expected: true),
    RenameGlobCase(glob: "a.b", path: "axb", expected: false),
    RenameGlobCase(glob: "a+b(c)", path: "a+b(c)", expected: true),
    RenameGlobCase(glob: "**/*.TS", path: "/a/b.ts", expected: false),
    RenameGlobCase(glob: "**/*.TS", path: "/a/b.ts", expected: true, ignoreCase: true)
]

@Suite
struct RenameFileGlobTests {
    @Test(arguments: renameGlobCases)
    func globMatchesLikeTheLspFileOperationPatternSyntax(_ item: RenameGlobCase) {
        #expect(
            LSPFileGlob.matches(item.glob, path: item.path, ignoreCase: item.ignoreCase) == item.expected
        )
    }

    @Test
    func unbalancedBracesHaveNoRegularExpression() {
        #expect(LSPFileGlob.regularExpression(for: "{a") == nil)
        #expect(LSPFileGlob.regularExpression(for: "{a}") == "(?:a)")
    }
}

@Suite
struct RenameFileOperationFilterTests {
    private func filter(
        _ glob: String,
        scheme: String? = nil,
        matches: FileOperationPatternKind? = nil,
        ignoreCase: Bool? = nil
    ) -> FileOperationFilter {
        FileOperationFilter(
            scheme: scheme,
            pattern: FileOperationPattern(
                glob: glob,
                matches: matches,
                options: ignoreCase.map { FileOperationPatternOptions(ignoreCase: $0) }
            )
        )
    }

    private func matches(
        _ filter: FileOperationFilter,
        uri: String = "file:///p/src/a/b.ts",
        isDirectory: Bool = false,
        rootPath: String? = nil
    ) -> Bool {
        LSPFileOperationFilterMatcher.matches(filter, uri: uri, isDirectory: isDirectory, rootPath: rootPath)
    }

    @Test
    func theSchemeMustMatchWhenTheFilterHasOne() {
        #expect(matches(filter("**/*.ts", scheme: "file")))
        #expect(matches(filter("**/*.ts", scheme: "FILE")))
        #expect(!matches(filter("**/*.ts", scheme: "untitled")))
        #expect(matches(filter("**/*.ts")))
        #expect(!matches(filter("**/*.ts", scheme: "file"), uri: "/p/src/a/b.ts"))
        #expect(matches(filter("**/*.ts"), uri: "/p/src/a/b.ts"))
    }

    @Test
    func thePatternKindSeparatesFilesFromFolders() {
        #expect(matches(filter("**/b.ts", matches: .file), isDirectory: false))
        #expect(!matches(filter("**/b.ts", matches: .file), isDirectory: true))
        #expect(matches(filter("**/b.ts", matches: .folder), isDirectory: true))
        #expect(!matches(filter("**/b.ts", matches: .folder), isDirectory: false))
        #expect(matches(filter("**/b.ts"), isDirectory: true))
        #expect(matches(filter("**/b.ts"), isDirectory: false))
    }

    @Test
    func ignoreCaseIsHonouredAndDefaultsToCaseSensitive() {
        #expect(!matches(filter("**/B.TS")))
        #expect(!matches(filter("**/B.TS", ignoreCase: false)))
        #expect(matches(filter("**/B.TS", ignoreCase: true)))
    }

    @Test
    func relativePatternsAreMatchedAgainstThePathInsideTheRoot() {
        let relative = filter("src/**/*.ts")

        #expect(!matches(relative))
        #expect(matches(relative, rootPath: "/p"))
        #expect(matches(relative, rootPath: "/p/"))
        #expect(!matches(relative, rootPath: "/q"))
        #expect(!matches(relative, rootPath: ""))
    }

    @Test
    func uriPathsArePercentDecodedAndTheAuthorityIsIgnored() {
        #expect(LSPFileOperationFilterMatcher.location(of: "file:///a/b%20c").path == "/a/b c")
        #expect(LSPFileOperationFilterMatcher.location(of: "file:///a/b%20c").scheme == "file")
        #expect(LSPFileOperationFilterMatcher.location(of: "file://host/x").path == "/x")
        #expect(LSPFileOperationFilterMatcher.location(of: "file://host").path.isEmpty)
        #expect(LSPFileOperationFilterMatcher.location(of: "file:///a/%zz").path == "/a/%zz")
        let plain = LSPFileOperationFilterMatcher.location(of: "/plain/path")
        #expect(plain.scheme == nil)
        #expect(plain.path == "/plain/path")
        #expect(matches(filter("**/b c.ts"), uri: "file:///p/b%20c.ts"))
        #expect(matches(filter("**/b c.ts"), uri: "file:///p/b c.ts"))
    }

    @Test
    func registrationOptionsMatchWhenAnyFilterMatches() {
        let options = FileOperationRegistrationOptions(filters: [filter("**/*.js"), filter("**/*.ts")])
        let none = FileOperationRegistrationOptions(filters: [])

        #expect(LSPFileOperationFilterMatcher.matches(
            options, uri: "file:///p/a.ts", isDirectory: false, rootPath: nil
        ))
        #expect(!LSPFileOperationFilterMatcher.matches(
            options, uri: "file:///p/a.rs", isDirectory: false, rootPath: nil
        ))
        #expect(!LSPFileOperationFilterMatcher.matches(
            none, uri: "file:///p/a.ts", isDirectory: false, rootPath: nil
        ))
    }
}
