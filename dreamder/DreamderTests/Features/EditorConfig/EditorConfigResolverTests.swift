import Foundation
import Synchronization
import Testing
@testable import Dreamder

private final class ReadLog: Sendable {
    let urls = Mutex<[String]>([])
}

struct EditorConfigPropertyCase: Sendable, CustomTestStringConvertible {
    let text: String
    let expected: EditorConfigProperties

    var testDescription: String { text.replacingOccurrences(of: "\n", with: " | ") }
}

struct EditorConfigResolverTests {
    static let propertyCases: [EditorConfigPropertyCase] = [
        EditorConfigPropertyCase(
            text: """
            [*]
            indent_style = space
            indent_size = 2
            tab_width = 4
            end_of_line = crlf
            insert_final_newline = true
            trim_trailing_whitespace = false
            charset = UTF-8
            max_line_length = 120
            """,
            expected: EditorConfigProperties(
                indentStyle: .space,
                indentSize: 2,
                tabWidth: 4,
                endOfLine: .crlf,
                insertFinalNewline: true,
                trimTrailingWhitespace: false,
                charset: "utf-8",
                maxLineLength: 120
            )
        ),
        EditorConfigPropertyCase(
            text: "[*]\nindent_style = tab",
            expected: EditorConfigProperties(indentStyle: .tab)
        ),
        EditorConfigPropertyCase(
            text: "[*]\nindent_style = tab\ntab_width = 8",
            expected: EditorConfigProperties(indentStyle: .tab, indentSize: 8, tabWidth: 8)
        ),
        EditorConfigPropertyCase(
            text: "[*]\nindent_size = tab\ntab_width = 3",
            expected: EditorConfigProperties(indentSize: 3, tabWidth: 3)
        ),
        EditorConfigPropertyCase(
            text: "[*]\nindent_size = TAB",
            expected: .empty
        ),
        EditorConfigPropertyCase(
            text: "[*]\nindent_size = 4",
            expected: EditorConfigProperties(indentSize: 4, tabWidth: 4)
        ),
        EditorConfigPropertyCase(
            text: "[*]\nindent_style = tab\nindent_size = 4\ntab_width = 8",
            expected: EditorConfigProperties(indentStyle: .tab, indentSize: 4, tabWidth: 8)
        ),
        EditorConfigPropertyCase(
            text: "[*]\nindent_style = tab\nindent_size = banana\ntab_width = 6",
            expected: EditorConfigProperties(indentStyle: .tab, indentSize: 6, tabWidth: 6)
        ),
        EditorConfigPropertyCase(
            text: "[*]\nindent_style = tab\nindent_size = 2\nindent_size = unset",
            expected: EditorConfigProperties(indentStyle: .tab)
        ),
        EditorConfigPropertyCase(
            text: """
            [*]
            indent_style = spaces
            indent_size = 0
            tab_width = x
            end_of_line = lf2
            insert_final_newline = yes
            trim_trailing_whitespace = 1
            charset =
            max_line_length = 0
            """,
            expected: .empty
        ),
        EditorConfigPropertyCase(text: "[*]\nindent_size = -1", expected: .empty),
        EditorConfigPropertyCase(text: "[*]\nindent_size = +4", expected: .empty),
        EditorConfigPropertyCase(text: "[*]\nindent_size = 4.5", expected: .empty),
        EditorConfigPropertyCase(
            text: "[*]\nmax_line_length = off",
            expected: .empty
        ),
        EditorConfigPropertyCase(
            text: "[*]\nmax_line_length = 80",
            expected: EditorConfigProperties(maxLineLength: 80)
        ),
        EditorConfigPropertyCase(
            text: "[*]\nmax_line_length = 80\nmax_line_length = off",
            expected: .empty
        ),
        EditorConfigPropertyCase(
            text: "[*]\nend_of_line = cr\ninsert_final_newline = FALSE\ntrim_trailing_whitespace = True",
            expected: EditorConfigProperties(
                endOfLine: .cr,
                insertFinalNewline: false,
                trimTrailingWhitespace: true
            )
        ),
        EditorConfigPropertyCase(
            text: "[*]\nend_of_line = lf\n[*.txt]\nend_of_line = unset\n[*.nomatch]\nend_of_line = cr",
            expected: .empty
        ),
        EditorConfigPropertyCase(
            text: "[*]\nindent_size = 2\n[a.txt]\nindent_size = 8",
            expected: EditorConfigProperties(indentSize: 8, tabWidth: 8)
        ),
        EditorConfigPropertyCase(
            text: "[*]\nindent_size = 2\n[a.txt]\nindent_size = nonsense",
            expected: .empty
        ),
        EditorConfigPropertyCase(
            text: "[*.md]\nindent_size = 2",
            expected: .empty
        ),
        EditorConfigPropertyCase(
            text: "indent_size = 2\n[*]\ncharset = latin1",
            expected: EditorConfigProperties(charset: "latin1")
        )
    ]

    private func restrictedResolver(to directory: URL) -> EditorConfigResolver {
        let prefix = directory.path(percentEncoded: false)
        return EditorConfigResolver { url in
            url.path(percentEncoded: false).hasPrefix(prefix) ? EditorConfigResolver.readFromDisk(url) : nil
        }
    }

    private func write(_ text: String, named name: String = ".editorconfig", in directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try text.write(to: directory.appending(path: name), atomically: true, encoding: .utf8)
    }

    @Test(arguments: propertyCases)
    func propertyTable(_ testCase: EditorConfigPropertyCase) {
        let configPath = "/proj/.editorconfig"
        let resolver = EditorConfigResolver { url in
            url.path(percentEncoded: false) == configPath ? testCase.text : nil
        }
        #expect(resolver.properties(for: URL(filePath: "/proj/a.txt")) == testCase.expected)
    }

    @Test func nearestFileWinsOverFartherOne() throws {
        try withTempDir { dir in
            try write("root = true\n[*.txt]\nindent_size = 8\nend_of_line = lf\n", in: dir)
            try write("[*.txt]\nindent_size = 2\n", in: dir.appending(path: "sub"))
            let resolver = restrictedResolver(to: dir)
            let nested = resolver.properties(for: dir.appending(path: "sub/deep/a.txt"))
            #expect(nested == EditorConfigProperties(indentSize: 2, tabWidth: 2, endOfLine: .lf))
            let top = resolver.properties(for: dir.appending(path: "a.txt"))
            #expect(top == EditorConfigProperties(indentSize: 8, tabWidth: 8, endOfLine: .lf))
        }
    }

    @Test func rootStopsTheWalk() throws {
        try withTempDir { dir in
            try write("[*]\nend_of_line = crlf\ncharset = latin1\n", in: dir)
            try write("root = true\n[*]\ncharset = utf-8\n", in: dir.appending(path: "mid"))
            try write("[*]\nindent_style = space\n", in: dir.appending(path: "mid/leaf"))
            let properties = restrictedResolver(to: dir).properties(for: dir.appending(path: "mid/leaf/f.txt"))
            #expect(properties == EditorConfigProperties(indentStyle: .space, charset: "utf-8"))
        }
    }

    @Test func rootFalseDoesNotStopTheWalk() throws {
        try withTempDir { dir in
            try write("[*]\ncharset = latin1\n", in: dir)
            try write("root = false\n", in: dir.appending(path: "mid"))
            let properties = restrictedResolver(to: dir).properties(for: dir.appending(path: "mid/f.txt"))
            #expect(properties == EditorConfigProperties(charset: "latin1"))
        }
    }

    @Test func laterSectionWinsWithinOneFile() throws {
        try withTempDir { dir in
            try write("[*.txt]\nindent_style = tab\ncharset = latin1\n[a.txt]\nindent_style = space\n[*]\ncharset = utf-16le\n", in: dir)
            let properties = restrictedResolver(to: dir).properties(for: dir.appending(path: "a.txt"))
            #expect(properties == EditorConfigProperties(indentStyle: .space, charset: "utf-16le"))
        }
    }

    @Test func nearerUnsetRemovesInheritedValue() throws {
        try withTempDir { dir in
            try write("[*]\ncharset = latin1\nend_of_line = lf\n", in: dir)
            try write("[*]\ncharset = unset\n", in: dir.appending(path: "sub"))
            let properties = restrictedResolver(to: dir).properties(for: dir.appending(path: "sub/f.txt"))
            #expect(properties == EditorConfigProperties(endOfLine: .lf))
        }
    }

    @Test func nearerFileSetsPropertyAfterFartherUnset() throws {
        try withTempDir { dir in
            try write("[*]\ncharset = unset\n", in: dir)
            try write("[*]\ncharset = utf-8\n", in: dir.appending(path: "sub"))
            let properties = restrictedResolver(to: dir).properties(for: dir.appending(path: "sub/f.txt"))
            #expect(properties == EditorConfigProperties(charset: "utf-8"))
        }
    }

    @Test func slashPatternsAreRelativeToTheirOwnConfigDirectory() throws {
        try withTempDir { dir in
            try write("[src/*.c]\nindent_size = 3\n[/top.c]\nindent_size = 5\n", in: dir)
            try write("[*.c]\ntab_width = 9\n[inner/*.c]\nend_of_line = cr\n", in: dir.appending(path: "src"))
            let resolver = restrictedResolver(to: dir)
            #expect(resolver.properties(for: dir.appending(path: "src/x.c")) == EditorConfigProperties(indentSize: 3, tabWidth: 9))
            #expect(resolver.properties(for: dir.appending(path: "src/inner/x.c")) == EditorConfigProperties(tabWidth: 9, endOfLine: .cr))
            #expect(resolver.properties(for: dir.appending(path: "top.c")) == EditorConfigProperties(indentSize: 5, tabWidth: 5))
            #expect(resolver.properties(for: dir.appending(path: "other/src/x.c")) == .empty)
        }
    }

    @Test func missingFilesAndEmptyDirectoriesYieldEmptyProperties() throws {
        try withTempDir { dir in
            let resolver = restrictedResolver(to: dir)
            #expect(resolver.properties(for: dir.appending(path: "nowhere/at/all/f.txt")) == .empty)
            try FileManager.default.createDirectory(at: dir.appending(path: "empty"), withIntermediateDirectories: true)
            #expect(resolver.properties(for: dir.appending(path: "empty/f.txt")) == .empty)
        }
    }

    @Test func fileInDirectoryWithoutConfigUsesAncestorConfig() throws {
        try withTempDir { dir in
            try write("[*.txt]\nindent_style = tab\n", in: dir)
            try FileManager.default.createDirectory(at: dir.appending(path: "a/b/c"), withIntermediateDirectories: true)
            let properties = restrictedResolver(to: dir).properties(for: dir.appending(path: "a/b/c/f.txt"))
            #expect(properties == EditorConfigProperties(indentStyle: .tab))
        }
    }

    @Test func configDirectoryNamedEditorconfigIsSkipped() throws {
        try withTempDir { dir in
            try FileManager.default.createDirectory(at: dir.appending(path: ".editorconfig"), withIntermediateDirectories: true)
            #expect(restrictedResolver(to: dir).properties(for: dir.appending(path: "f.txt")) == .empty)
        }
    }

    @Test func readFromDiskReturnsTextOrNil() throws {
        try withTempDir { dir in
            try write("root = true\n", in: dir)
            #expect(EditorConfigResolver.readFromDisk(dir.appending(path: ".editorconfig")) == "root = true\n")
            #expect(EditorConfigResolver.readFromDisk(dir.appending(path: "missing")) == nil)
            #expect(EditorConfigResolver.readFromDisk(dir) == nil)
        }
    }

    @Test func defaultResolverReadsFromDisk() throws {
        try withTempDir { dir in
            try write("root = true\n[*.txt]\nindent_style = space\n", in: dir)
            let properties = EditorConfigResolver().properties(for: dir.appending(path: "f.txt"))
            #expect(properties == EditorConfigProperties(indentStyle: .space))
        }
    }

    @Test func walkReadsNearestDirectoryFirstUpToTheFilesystemRoot() {
        let log = ReadLog()
        let resolver = EditorConfigResolver { url in
            log.urls.withLock { $0.append(url.path(percentEncoded: false)) }
            return nil
        }
        #expect(resolver.properties(for: URL(filePath: "/a/b/c/f.swift")) == .empty)
        #expect(log.urls.withLock { $0 } == [
            "/a/b/c/.editorconfig",
            "/a/b/.editorconfig",
            "/a/.editorconfig",
            "/.editorconfig"
        ])
    }

    @Test func walkStopsAfterTheRootFileAndAppliesFarthestFirst() {
        let log = ReadLog()
        let files = [
            "/a/b/c/.editorconfig": "[*.swift]\nindent_size = 1\n",
            "/a/b/.editorconfig": "root = true\n[c/*.swift]\nindent_size = 2\ncharset = utf-8\n",
            "/a/.editorconfig": "[*.swift]\nindent_size = 3\nend_of_line = lf\n"
        ]
        let resolver = EditorConfigResolver { url in
            let path = url.path(percentEncoded: false)
            log.urls.withLock { $0.append(path) }
            return files[path]
        }
        let properties = resolver.properties(for: URL(filePath: "/a/b/c/f.swift"))
        #expect(properties == EditorConfigProperties(indentSize: 1, tabWidth: 1, charset: "utf-8"))
        #expect(log.urls.withLock { $0 } == ["/a/b/c/.editorconfig", "/a/b/.editorconfig"])
    }

    @Test func filesDirectlyUnderTheFilesystemRootAreResolved() {
        let resolver = EditorConfigResolver { url in
            url.path(percentEncoded: false) == "/.editorconfig" ? "[*.txt]\ncharset = latin1\n" : nil
        }
        #expect(resolver.properties(for: URL(filePath: "/f.txt")) == EditorConfigProperties(charset: "latin1"))
    }
}
