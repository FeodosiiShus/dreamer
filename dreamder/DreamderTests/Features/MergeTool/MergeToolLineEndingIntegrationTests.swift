import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct MergeToolLineEndingIntegrationTests {
    private static let path = "lines.txt"

    private static func crlf(_ lines: [String]) -> [UInt8] {
        GitMergeFixture.utf8Bytes(lines.joined(separator: "\r\n") + "\r\n")
    }

    private static let crlfBase = crlf(["alpha", "beta", "gamma", "delta", "epsilon", "zeta", "eta", "theta"])
    private static let crlfOurs = crlf(["alpha", "beta-main", "gamma", "delta", "epsilon", "zeta-main", "eta", "theta"])
    private static let crlfTheirs = crlf([
        "alpha", "beta", "gamma", "delta", "epsilon", "zeta-feature", "eta", "theta-feature"
    ])
    private static let crlfMergedLeft = crlf([
        "alpha", "beta-main", "gamma", "delta", "epsilon", "zeta-main", "eta", "theta-feature"
    ])

    private func makeModel(_ root: URL) throws -> MergeRevisionsViewModel {
        let document = WorkspaceDocument()
        document.sourceControlManager = SourceControlManager(workspaceURL: root, editorManager: EditorManager())
        return try #require(MergeRevisionsViewModel(workspace: document, path: Self.path, autoLoad: false))
    }

    private func crlfConflict(in root: URL) async throws -> GitMergeFixture {
        try await GitMergeFixture.byteConflict(
            in: root,
            path: Self.path,
            base: Self.crlfBase,
            ours: Self.crlfOurs,
            theirs: Self.crlfTheirs
        )
    }

    private func loadedCRLFModel(_ root: URL) async throws -> (GitMergeFixture, MergeRevisionsViewModel) {
        let fixture = try await crlfConflict(in: root)
        let model = try makeModel(root)
        await model.load()
        return (fixture, model)
    }

    private func loneLineFeedCount(in bytes: [UInt8]) -> Int {
        var count = 0
        var previous: UInt8 = 0
        for byte in bytes {
            if byte == 10 && previous != 13 {
                count += 1
            }
            previous = byte
        }
        return count
    }

    @Test
    func applyingAResolvedCRLFFileKeepsEveryCRLF() async throws {
        try await withTempDir { dir in
            let (fixture, model) = try await loadedCRLFModel(dir)
            let conflict = try #require(model.merge?.blocks.first { $0.kind == .conflict })

            await model.requestApplyNonConflicting(.all, window: nil)
            await model.requestResolve(conflict.id, with: .left, window: nil)
            let applied = await model.apply()

            #expect(applied)
            let written = try fixture.readBytes(Self.path)
            #expect(written == Self.crlfMergedLeft)
            #expect(loneLineFeedCount(in: written) == 0)
            #expect(try await fixture.unmergedPaths().isEmpty)
            #expect(try await fixture.indexMatchesWorktree(Self.path))
        }
    }

    @Test
    func handEditedTextIsWrittenWithTheFilesLineEnding() async throws {
        try await withTempDir { dir in
            let (fixture, model) = try await loadedCRLFModel(dir)

            model.userEditedResult("typed\nby\nhand\n")
            let applied = await model.apply()

            #expect(model.resultText == "typed\r\nby\r\nhand\r\n")
            #expect(applied)
            #expect(try fixture.readBytes(Self.path) == GitMergeFixture.utf8Bytes("typed\r\nby\r\nhand\r\n"))
        }
    }

    @Test
    func acceptingASideOfACRLFFileKeepsItsBytes() async throws {
        try await withTempDir { dir in
            let (fixture, model) = try await loadedCRLFModel(dir)

            let finished = await model.requestAcceptSide(.theirs, window: nil)

            #expect(finished)
            #expect(try fixture.readBytes(Self.path) == Self.crlfTheirs)
            #expect(try await fixture.indexMatchesWorktree(Self.path))
        }
    }

    @Test
    func carriageReturnOnlyFilesKeepTheirLineEndings() async throws {
        try await withTempDir { dir in
            let fixture = try await GitMergeFixture.byteConflict(
                in: dir,
                path: Self.path,
                base: GitMergeFixture.utf8Bytes("one\rtwo\rthree\rfour\r"),
                ours: GitMergeFixture.utf8Bytes("one\rTWO\rthree\rfour\r"),
                theirs: GitMergeFixture.utf8Bytes("one\rtwo\rthree\rFOUR\r")
            )
            let model = try makeModel(dir)
            await model.load()

            await model.requestApplyNonConflicting(.all, window: nil)
            let applied = await model.apply()

            #expect(applied)
            #expect(try fixture.readBytes(Self.path) == GitMergeFixture.utf8Bytes("one\rTWO\rthree\rFOUR\r"))
        }
    }

    @Test
    func aDeliberatelyRemovedFinalNewlineStaysRemoved() async throws {
        try await withTempDir { dir in
            let fixture = try await GitMergeFixture.byteConflict(
                in: dir,
                path: Self.path,
                base: GitMergeFixture.utf8Bytes("a\nb\nc\n"),
                ours: GitMergeFixture.utf8Bytes("a\nL\nc"),
                theirs: GitMergeFixture.utf8Bytes("a\nR\nc\n")
            )
            let model = try makeModel(dir)
            await model.load()
            let conflict = try #require(model.merge?.blocks.first { $0.kind == .conflict })

            await model.requestResolve(conflict.id, with: .left, window: nil)
            let applied = await model.apply()

            #expect(applied)
            #expect(try fixture.readBytes(Self.path) == GitMergeFixture.utf8Bytes("a\nL\nc"))
        }
    }

    @Test
    func lineFeedFilesAreUnchangedByTheFix() async throws {
        try await withTempDir { dir in
            let fixture = try await GitMergeFixture.byteConflict(
                in: dir,
                path: Self.path,
                base: GitMergeFixture.utf8Bytes("a\nb\nc\n"),
                ours: GitMergeFixture.utf8Bytes("a\nL\nc\n"),
                theirs: GitMergeFixture.utf8Bytes("a\nR\nc\n")
            )
            let model = try makeModel(dir)
            await model.load()
            let conflict = try #require(model.merge?.blocks.first { $0.kind == .conflict })

            await model.requestResolve(conflict.id, with: .right, window: nil)
            _ = await model.apply()

            #expect(try fixture.readBytes(Self.path) == GitMergeFixture.utf8Bytes("a\nR\nc\n"))
        }
    }
}
