import Foundation
import Testing
@testable import Dreamder

struct ConsoleFileLinkResolverTests {
    private func touch(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "x".write(to: url, atomically: true, encoding: .utf8)
    }

    private func link(_ path: String, line: Int? = nil, column: Int? = nil) -> ConsoleFileLink {
        ConsoleFileLink(range: 0..<path.count, path: path, line: line, column: column)
    }

    @Test
    func absolutePathsResolveAsIs() throws {
        try withTempDir { directory in
            let file = directory.appending(path: "Sources/File.swift")
            try touch(file)
            let resolver = ConsoleFileLinkResolver(baseDirectories: [])

            let target = try #require(resolver.target(for: link(file.path(percentEncoded: false), line: 12, column: 5)))

            #expect(target.url.standardizedFileURL == file.standardizedFileURL)
            #expect(target.line == 12)
            #expect(target.column == 5)
        }
    }

    @Test
    func missingLineAndColumnDefaultToOne() throws {
        try withTempDir { directory in
            let file = directory.appending(path: "a.swift")
            try touch(file)
            let resolver = ConsoleFileLinkResolver(baseDirectories: [directory])

            let target = try #require(resolver.target(for: link("a.swift")))

            #expect(target.line == 1)
            #expect(target.column == 1)
        }
    }

    @Test
    func nonPositiveLinesAndColumnsAreClampedToOne() throws {
        try withTempDir { directory in
            try touch(directory.appending(path: "a.swift"))
            let resolver = ConsoleFileLinkResolver(baseDirectories: [directory])

            let target = try #require(resolver.target(path: "a.swift", line: 0, column: 0))

            #expect(target.line == 1)
            #expect(target.column == 1)
        }
    }

    @Test
    func relativePathsAreTriedAgainstTheBaseDirectoriesInOrder() throws {
        try withTempDir { directory in
            let first = directory.appending(path: "first", directoryHint: .isDirectory)
            let second = directory.appending(path: "second", directoryHint: .isDirectory)
            try touch(first.appending(path: "both.swift"))
            try touch(second.appending(path: "both.swift"))
            try touch(second.appending(path: "only-second.swift"))
            let resolver = ConsoleFileLinkResolver(baseDirectories: [first, second])

            let both = try #require(resolver.target(for: link("both.swift", line: 2)))
            let onlySecond = try #require(resolver.target(for: link("only-second.swift", line: 3)))

            #expect(both.url.standardizedFileURL == first.appending(path: "both.swift").standardizedFileURL)
            #expect(onlySecond.url.standardizedFileURL == second.appending(path: "only-second.swift").standardizedFileURL)
            #expect(onlySecond.line == 3)
        }
    }

    @Test
    func dotSegmentsAreStandardized() throws {
        try withTempDir { directory in
            let file = directory.appending(path: "pkg/a.swift")
            try touch(file)
            let resolver = ConsoleFileLinkResolver(
                baseDirectories: [directory.appending(path: "pkg", directoryHint: .isDirectory)]
            )

            let dotted = try #require(resolver.target(for: link("./sub/../a.swift")))
            let parent = try #require(resolver.target(for: link("../pkg/a.swift")))

            #expect(dotted.url == file.standardizedFileURL)
            #expect(parent.url == file.standardizedFileURL)
        }
    }

    @Test
    func missingFilesAndEmptyBasesResolveToNothing() throws {
        try withTempDir { directory in
            try touch(directory.appending(path: "present.swift"))
            let withBase = ConsoleFileLinkResolver(baseDirectories: [directory])
            let withoutBase = ConsoleFileLinkResolver(baseDirectories: [])

            #expect(withBase.target(for: link("missing.swift", line: 1)) == nil)
            #expect(withBase.target(for: link(directory.appending(path: "missing.swift").path(percentEncoded: false))) == nil)
            #expect(withoutBase.target(for: link("present.swift")) == nil)
        }
    }

    @Test
    func directoriesAreNotFileTargets() throws {
        try withTempDir { directory in
            try FileManager.default.createDirectory(
                at: directory.appending(path: "folder.swift", directoryHint: .isDirectory),
                withIntermediateDirectories: true
            )
            let resolver = ConsoleFileLinkResolver(baseDirectories: [directory])

            #expect(resolver.target(for: link("folder.swift")) == nil)
            #expect(ConsoleFileLinkResolver.isRegularFile(atPath: directory.path(percentEncoded: false)) == false)
        }
    }

    @Test
    func regularFileCheckAcceptsFilesOnly() throws {
        try withTempDir { directory in
            let file = directory.appending(path: "a.swift")
            try touch(file)

            #expect(ConsoleFileLinkResolver.isRegularFile(atPath: file.path(percentEncoded: false)))
            #expect(!ConsoleFileLinkResolver.isRegularFile(atPath: directory.appending(path: "none").path(percentEncoded: false)))
        }
    }

    @Test
    func tildePathsExpandToTheHomeDirectory() throws {
        let home = NSHomeDirectory()
        let resolver = ConsoleFileLinkResolver(baseDirectories: [], fileExists: { $0 == home + "/proj/a.swift" })
        let homeResolver = ConsoleFileLinkResolver(baseDirectories: [], fileExists: { $0 == home })

        let target = try #require(resolver.target(for: link("~/proj/a.swift", line: 4)))
        let homeTarget = try #require(homeResolver.target(for: link("~")))

        #expect(target.url.path(percentEncoded: false) == home + "/proj/a.swift")
        #expect(target.line == 4)
        #expect(homeTarget.url.path(percentEncoded: false) == home)
        #expect(resolver.target(for: link("~other/a.swift")) == nil)
    }

    @Test
    func theExistenceCheckReceivesTheStandardizedPath() throws {
        let base = URL(filePath: "/base/dir", directoryHint: .isDirectory)
        let resolver = ConsoleFileLinkResolver(baseDirectories: [base], fileExists: { $0 == "/base/x/a.swift" })

        let target = try #require(resolver.target(for: link("../x/a.swift", line: 9)))

        #expect(target.url.path(percentEncoded: false) == "/base/x/a.swift")
        #expect(target.line == 9)
    }
}

struct ConsoleFileLinkPayloadTests {
    private func splitLikeTheTerminal(_ cell: String) throws -> (link: String, params: [String: String]) {
        let parts = cell.split(separator: ";", maxSplits: Int.max, omittingEmptySubsequences: false)
        #expect(parts.count == 2)
        var params: [String: String] = [:]
        for pair in parts[0].split(separator: ":") {
            let keyValue = pair.split(separator: "=")
            if keyValue.count == 2 { params[String(keyValue[0])] = String(keyValue[1]) }
        }
        return (String(parts[1]), params)
    }

    @Test
    func simplePathsEncodeLineColumnAndPath() {
        let payload = ConsoleFileLinkPayload(path: "/tmp/x.swift", line: 12, column: 5)

        #expect(payload.cellValue == "line=12:column=5;/tmp/x.swift")
    }

    @Test
    func reservedAndNonAsciiBytesArePercentEncodedWithUppercaseHex() {
        let payload = ConsoleFileLinkPayload(path: "/tmp/a b;c:d%é.swift", line: 1, column: 2)

        #expect(payload.cellValue == "line=1:column=2;/tmp/a%20b%3Bc%3Ad%25%C3%A9.swift")
    }

    @Test(arguments: [
        "/tmp/plain.swift",
        "/tmp/with space/a b.swift",
        "/tmp/semi;colon:percent%/f;g:h%i.swift",
        "/tmp/ünïcode/файл.rs",
        "/tmp/eq=ual/a=b.swift"
    ])
    func payloadsRoundTripThroughTheTerminalSplit(_ path: String) throws {
        let payload = ConsoleFileLinkPayload(path: path, line: 321, column: 7)

        let (link, params) = try splitLikeTheTerminal(payload.cellValue)
        let decoded = try #require(ConsoleFileLinkPayload(link: link, params: params))

        #expect(decoded == payload)
        #expect(!link.contains(";"))
        #expect(!link.contains(":"))
    }

    @Test
    func payloadsAreBuiltFromResolverTargets() {
        let target = ConsoleFileLinkTarget(url: URL(filePath: "/tmp/a b.swift"), line: 3, column: 9)

        let payload = ConsoleFileLinkPayload(target: target)

        #expect(payload == ConsoleFileLinkPayload(path: "/tmp/a b.swift", line: 3, column: 9))
    }

    @Test
    func malformedLinksAreRejected() {
        #expect(ConsoleFileLinkPayload(link: "/tmp/a.swift", params: [:]) == nil)
        #expect(ConsoleFileLinkPayload(link: "/tmp/a.swift", params: ["line": "1"]) == nil)
        #expect(ConsoleFileLinkPayload(link: "/tmp/a.swift", params: ["column": "1"]) == nil)
        #expect(ConsoleFileLinkPayload(link: "/tmp/a.swift", params: ["line": "x", "column": "1"]) == nil)
        #expect(ConsoleFileLinkPayload(link: "/tmp/a.swift", params: ["line": "1", "column": "y"]) == nil)
        #expect(ConsoleFileLinkPayload(link: "%zz", params: ["line": "1", "column": "1"]) == nil)
    }
}
