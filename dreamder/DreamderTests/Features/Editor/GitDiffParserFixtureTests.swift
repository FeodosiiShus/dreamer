import Foundation
import Testing
@testable import Dreamder

nonisolated struct PatchHeaderFixture: Sendable, CustomStringConvertible {
    let path: String
    let headers: [String]
    let patchText: String

    var description: String { path }
}

nonisolated enum PatchHeaderFixtures {
    static let sources: [(directory: String, fileName: String)] = [
        ("platform/platform-tests/testData/diff/patch", "expected.patch"),
        ("platform/platform-tests/testData/diff/patchReader", "test.patch"),
        ("platform/platform-tests/testData/diff/applyPatch", "apply.patch")
    ]

    static func all() throws -> [PatchHeaderFixture] {
        let manager = FileManager.default
        var fixtures: [PatchHeaderFixture] = []
        for source in sources {
            let names = try IntelliJTestData.files(in: source.directory, suffix: "")
            for name in names {
                let relativePath = "\(source.directory)/\(name)/\(source.fileName)"
                let url = IntelliJTestData.url(relativePath)
                guard let data = manager.contents(atPath: url.path(percentEncoded: false)) else { continue }
                let text = String(decoding: data, as: UTF8.self)
                let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
                    .map { $0.hasSuffix("\r") ? String($0.dropLast()) : String($0) }
                let headers = lines.filter { $0.hasPrefix("@@") }
                guard !headers.isEmpty else { continue }
                fixtures.append(PatchHeaderFixture(path: relativePath, headers: headers, patchText: lines.joined(separator: "\n")))
            }
        }
        return fixtures
    }

    static func expectedHunk(forHeader header: String) -> GitDiffParser.Hunk? {
        let pattern = /^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/
        guard let match = header.firstMatch(of: pattern),
              let oldStart = Int(match.1),
              let newStart = Int(match.3) else { return nil }
        return GitDiffParser.Hunk(
            oldStart: oldStart,
            oldCount: match.2.flatMap { Int($0) } ?? 1,
            newStart: newStart,
            newCount: match.4.flatMap { Int($0) } ?? 1
        )
    }
}

@Suite
struct GitDiffParserFixtureTests {
    static let fixtures: [PatchHeaderFixture] = (try? PatchHeaderFixtures.all()) ?? []

    @Test
    func patchFixturesAreDiscovered() {
        #expect(Self.fixtures.count > 50)
        #expect(Self.fixtures.flatMap(\.headers).count > 70)
    }

    @Test(arguments: fixtures)
    func everyHunkHeaderParsesToTheNumbersItSpells(fixture: PatchHeaderFixture) throws {
        for header in fixture.headers {
            let expected = try #require(PatchHeaderFixtures.expectedHunk(forHeader: header), "unparsable fixture header \(header)")
            #expect(GitDiffParser.hunk(fromHeader: Substring(header)) == expected, "\(header)")
        }
    }

    @Test(arguments: fixtures)
    func wholePatchYieldsOneHunkPerHeaderInOrder(fixture: PatchHeaderFixture) {
        let expected = fixture.headers.compactMap(PatchHeaderFixtures.expectedHunk(forHeader:))
        #expect(GitDiffParser.hunks(inDiff: fixture.patchText) == expected)
    }

    @Test(arguments: fixtures)
    func lineChangesCoverEveryNonEmptyHunk(fixture: PatchHeaderFixture) throws {
        for header in fixture.headers {
            let hunk = try #require(GitDiffParser.hunk(fromHeader: Substring(header)), "\(header)")
            let change = GitLineChange(hunk: hunk)
            guard hunk.oldCount + hunk.newCount > 0 else {
                #expect(change == nil, "\(header)")
                continue
            }
            let unwrapped = try #require(change, "\(header)")
            let expectedOld = hunk.oldCount > 0 ? hunk.oldStart...(hunk.oldStart + hunk.oldCount - 1) : nil
            let expectedNew = hunk.newCount > 0 ? hunk.newStart...(hunk.newStart + hunk.newCount - 1) : nil
            #expect(unwrapped.oldLines == expectedOld, "\(header)")
            #expect(unwrapped.newLines == expectedNew, "\(header)")
            let expectedKind: GitLineChange.Kind = hunk.oldCount == 0 ? .added : hunk.newCount == 0 ? .deleted : .modified
            #expect(unwrapped.kind == expectedKind, "\(header)")
        }
    }
}
