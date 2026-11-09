import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct ReplaceInFilesTests {
    static let allFailedOne =
        "All files failed to update. (1) errors occurred. Check logs for more information"
    static let allFailedTwo =
        "All files failed to update. (2) errors occurred. Check logs for more information"
    static let oneUpdatedOneFailed =
        "1 successfully updated, 1 errors occurred. Please check logs for more information."

    func usage(
        _ location: Int,
        _ length: Int,
        _ replacement: String?,
        from start: (Int, Int),
        to end: (Int, Int)
    ) -> FindUsage {
        FindUsage(
            range: NSRange(location: location, length: length),
            replacement: replacement,
            start: FindTextPosition(line: start.0, column: start.1),
            end: FindTextPosition(line: end.0, column: end.1)
        )
    }

    func permissions(_ path: String, in dir: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: dir.appending(path: path).path)
        return try #require((attributes[.posixPermissions] as? NSNumber)?.intValue)
    }

    func inode(_ path: String, in dir: URL) throws -> UInt64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: dir.appending(path: path).path)
        return try #require((attributes[.systemFileNumber] as? NSNumber)?.uint64Value)
    }

    func setPermissions(_ mode: Int, _ path: String, in dir: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: dir.appending(path: path).path)
    }

    @Test
    func plainTextPreviewsCarryUsagesAndReplacementLines() async throws {
        try await withTempDir { dir in
            let (workspace, state) = try await FindStateSupport.replaceSession(
                files: ["a.txt": "let needle = 1\n  needle again\n"],
                query: "needle",
                replacement: "thread",
                in: dir
            )
            defer { workspace.close() }

            let matches = FindStateSupport.matches("a.txt", in: state)
            #expect(state.findNavigatorStatus == .found)
            #expect(state.replacementError == nil)
            #expect(matches.count == 2)
            let firstMatch = try matches.required(at: 0)
            let secondMatch = try matches.required(at: 1)
            #expect(firstMatch.usage == usage(4, 6, "thread", from: (1, 5), to: (1, 11)))
            #expect(secondMatch.usage == usage(17, 6, "thread", from: (2, 3), to: (2, 9)))
            #expect(firstMatch.replacementPreviewLine == "let thread = 1")
            #expect(secondMatch.replacementPreviewLine == "thread again")
            #expect(firstMatch.replacementDisplay == "thread")
        }
    }

    @Test
    func findModeSearchesCarryNoReplacements() async throws {
        try await withTempDir { dir in
            try FindStateSupport.write("needle\n", "a.txt", in: dir)
            let (workspace, state) = try await FindStateSupport.prepare(in: dir)
            defer { workspace.close() }
            state.replaceText = "thread"

            await state.search("needle")

            let match = try #require(FindStateSupport.matches("a.txt", in: state).first)
            #expect(match.usage == usage(0, 6, nil, from: (1, 1), to: (1, 7)))
            #expect(match.replacementPreviewLine == nil)
            #expect(match.replacementDisplay == nil)
        }
    }

    @Test
    func regexGroupReferencesAreExpandedInPreviews() async throws {
        try await withTempDir { dir in
            let (workspace, state) = try await FindStateSupport.replaceSession(
                files: ["a.txt": "hello world\nfoo bar\n"],
                query: "(\\w+) (\\w+)",
                replacement: "$2 $1",
                regex: true,
                in: dir
            )
            defer { workspace.close() }

            let matches = FindStateSupport.matches("a.txt", in: state)
            #expect(matches.map { $0.usage?.replacement } == ["world hello", "bar foo"])
            #expect(matches.map(\.replacementPreviewLine) == ["world hello", "bar foo"])
        }
    }

    @Test
    func namedGroupsAndCaseConversionAreExpandedInPreviews() async throws {
        try await withTempDir { dir in
            let (workspace, state) = try await FindStateSupport.replaceSession(
                files: ["a.txt": "hello world\n"],
                query: "(?<word>h\\w+) w\\w+",
                replacement: "\\U${word}\\E!",
                regex: true,
                in: dir
            )
            defer { workspace.close() }

            try await eventually {
                FindStateSupport.matches("a.txt", in: state).first?.usage?.replacement == "HELLO!"
            }

            state.replaceText = "${word}/${word}"
            await state.search("(?<word>h\\w+) w\\w+")
            try await eventually {
                FindStateSupport.matches("a.txt", in: state).first?.usage?.replacement == "hello/hello"
            }
        }
    }

    @Test
    func preserveCaseFollowsTheFoundText() async throws {
        try await withTempDir { dir in
            let (workspace, state) = try await FindStateSupport.replaceSession(
                files: ["a.txt": "needle Needle NEEDLE\n"],
                query: "needle",
                replacement: "thread",
                preserveCase: true,
                in: dir
            )
            defer { workspace.close() }

            let matches = FindStateSupport.matches("a.txt", in: state)
            #expect(matches.map { $0.usage?.replacement } == ["thread", "Thread", "THREAD"])
            #expect(try matches.required(at: 1).replacementPreviewLine == "needle Thread NEEDLE")
        }
    }

    @Test
    func invalidTemplateReportsTheErrorAndComputesNoPreviews() async throws {
        try await withTempDir { dir in
            let (workspace, state) = try await FindStateSupport.replaceSession(
                files: ["a.txt": "a\n"],
                query: "(a)",
                replacement: "$5",
                regex: true,
                in: dir
            )
            defer { workspace.close() }

            #expect(state.replacementError == "No group 5")
            #expect(state.findNavigatorStatus == .found)
            let match = try #require(FindStateSupport.matches("a.txt", in: state).first)
            #expect(match.usage?.replacement == nil)
            #expect(match.replacementPreviewLine == nil)
        }
    }

    @Test
    func replaceAllRewritesFilesInPlaceKeepingPermissionsAndInode() async throws {
        try await withTempDir { dir in
            try FindStateSupport.write("needle one\nneedle two\n", "a.txt", in: dir)
            try setPermissions(0o751, "a.txt", in: dir)
            let permissionsBefore = try permissions("a.txt", in: dir)
            let inodeBefore = try inode("a.txt", in: dir)
            let (workspace, state) = try await FindStateSupport.replaceSession(
                files: ["b.txt": "needle\n", "c.txt": "untouched\n"],
                query: "needle",
                replacement: "thread",
                in: dir
            )
            defer { workspace.close() }
            #expect(state.searchResultsFileCount == 2)
            #expect(state.searchResultsCount == 3)

            await state.replaceAll()

            #expect(try FindStateSupport.read("a.txt", in: dir) == "thread one\nthread two\n")
            #expect(try FindStateSupport.read("b.txt", in: dir) == "thread\n")
            #expect(try FindStateSupport.read("c.txt", in: dir) == "untouched\n")
            #expect(try permissions("a.txt", in: dir) == permissionsBefore)
            #expect(permissionsBefore == 0o751)
            #expect(try inode("a.txt", in: dir) == inodeBefore)
            #expect(state.findNavigatorStatus == .replaced(updatedFiles: 2))
            #expect(state.searchResult.isEmpty)
            #expect(state.searchResultsCount == 0)
            #expect(state.searchResultsFileCount == 0)
            #expect(state.replaceNotice == nil)
            #expect(state.resultSelection == nil)
        }
    }

    @Test
    func replacingOneMatchRebasesTheRemainingMatchesOfTheFile() async throws {
        try await withTempDir { dir in
            let (workspace, state) = try await FindStateSupport.replaceSession(
                files: ["a.txt": "needle needle\nxx needle\n"],
                query: "needle",
                replacement: "thread!",
                in: dir
            )
            defer { workspace.close() }

            await state.replace(try FindStateSupport.matches("a.txt", in: state).required(at: 0))

            #expect(try FindStateSupport.read("a.txt", in: dir) == "thread! needle\nxx needle\n")
            var remaining = FindStateSupport.matches("a.txt", in: state)
            #expect(remaining.count == 2)
            let firstRemaining = try remaining.required(at: 0)
            let secondRemaining = try remaining.required(at: 1)
            #expect(firstRemaining.usage == usage(8, 6, "thread!", from: (1, 9), to: (1, 15)))
            #expect(firstRemaining.lineContent == "thread! needle")
            #expect(secondRemaining.usage == usage(18, 6, "thread!", from: (2, 4), to: (2, 10)))
            #expect(secondRemaining.lineContent == "xx needle")
            #expect(state.findNavigatorStatus == .found)
            #expect(state.replaceNotice == nil)
            #expect(state.searchResultsCount == 2)
            #expect(state.searchResultsFileCount == 1)

            await state.replace(firstRemaining)

            #expect(try FindStateSupport.read("a.txt", in: dir) == "thread! thread!\nxx needle\n")
            remaining = FindStateSupport.matches("a.txt", in: state)
            #expect(remaining.count == 1)
            #expect(try remaining.required(at: 0).usage == usage(19, 6, "thread!", from: (2, 4), to: (2, 10)))

            await state.replaceAll()

            #expect(try FindStateSupport.read("a.txt", in: dir) == "thread! thread!\nxx thread!\n")
            #expect(state.findNavigatorStatus == .replaced(updatedFiles: 1))
        }
    }
}
