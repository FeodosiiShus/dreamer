import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct MergeToolNonUTF8Tests {
    private static let path = "notes.txt"
    private static let undecodableMessage = "This file is not valid UTF-8 and cannot be merged here. "
        + "Use Accept Left or Accept Right to take one side with Git."

    private static func latin1(_ text: String) -> [UInt8] {
        GitMergeFixture.latin1Bytes(text)
    }

    private static let latin1Base = latin1("intro\ncaf\u{E9}\nend\n")
    private static let latin1Ours = latin1("intro\ncaf\u{E9} main\nend\n")
    private static let latin1Theirs = latin1("intro\ncaf\u{E9} feature\nend\n")

    private func repository(_ root: URL) -> MergeConflictRepository {
        MergeConflictRepository(
            gitClient: GitClient(directoryURL: root, shellClient: .live()),
            rootURL: root
        )
    }

    private func makeModel(_ root: URL) throws -> MergeRevisionsViewModel {
        let document = WorkspaceDocument()
        document.sourceControlManager = SourceControlManager(workspaceURL: root, editorManager: EditorManager())
        return try #require(MergeRevisionsViewModel(workspace: document, path: Self.path, autoLoad: false))
    }

    private func latin1Conflict(in root: URL) async throws -> GitMergeFixture {
        try await GitMergeFixture.byteConflict(
            in: root,
            path: Self.path,
            base: Self.latin1Base,
            ours: Self.latin1Ours,
            theirs: Self.latin1Theirs
        )
    }

    @Test
    func stageContentFlagsOnlyUndecodableText() {
        typealias Content = MergeConflictRepository.StageContent
        typealias Revisions = MergeConflictRepository.RevisionSet
        let text = Content.text("a")

        #expect(Content.notUTF8.isNotUTF8)
        #expect(Content.notUTF8.isBinary == false)
        #expect(Content.notUTF8.text.isEmpty)
        #expect(text.isNotUTF8 == false)
        #expect(Content.missing.isNotUTF8 == false)
        #expect(Content.binary.isNotUTF8 == false)
        #expect(Revisions(base: text, ours: text, theirs: text).isNotUTF8 == false)
        #expect(Revisions(base: .notUTF8, ours: text, theirs: text).isNotUTF8)
        #expect(Revisions(base: text, ours: .notUTF8, theirs: text).isNotUTF8)
        #expect(Revisions(base: text, ours: text, theirs: .notUTF8).isNotUTF8)
    }

    @Test
    func everyStageOfALatin1ConflictIsReportedAsNotUTF8InsteadOfRepairedText() async throws {
        try await withTempDir { dir in
            _ = try await latin1Conflict(in: dir)

            let revisions = await repository(dir).revisions(for: Self.path)

            #expect(revisions.base == .notUTF8)
            #expect(revisions.ours == .notUTF8)
            #expect(revisions.theirs == .notUTF8)
            #expect(revisions.isNotUTF8)
            #expect(revisions.isBinary == false)
        }
    }

    @Test
    func oneUndecodableStageIsEnoughToBlockTheMerge() async throws {
        try await withTempDir { dir in
            _ = try await GitMergeFixture.byteConflict(
                in: dir,
                path: Self.path,
                base: GitMergeFixture.utf8Bytes("intro\ncafe\nend\n"),
                ours: Self.latin1Ours,
                theirs: GitMergeFixture.utf8Bytes("intro\ncafe feature\nend\n")
            )

            let revisions = await repository(dir).revisions(for: Self.path)

            #expect(revisions.base == .text("intro\ncafe\nend\n"))
            #expect(revisions.ours == .notUTF8)
            #expect(revisions.theirs == .text("intro\ncafe feature\nend\n"))
            #expect(revisions.isNotUTF8)
        }
    }

    @Test
    func loadingRefusesToMergeAndOffersTheSidesThroughGit() async throws {
        try await withTempDir { dir in
            _ = try await latin1Conflict(in: dir)
            let model = try makeModel(dir)

            await model.load()

            #expect(model.errorMessage == Self.undecodableMessage)
            #expect(model.isLoading == false)
            #expect(model.isConflictValid)
            #expect(model.isUndecodable)
            #expect(model.merge == nil)
            #expect(model.summary.isEmpty)
            #expect(model.canApply == false)
            #expect(model.canAcceptSide)
        }
    }

    @Test
    func applyNeverWritesRepairedText() async throws {
        try await withTempDir { dir in
            let fixture = try await latin1Conflict(in: dir)
            let model = try makeModel(dir)
            await model.load()
            let before = try fixture.readBytes(Self.path)

            let applied = await model.apply()

            #expect(applied == false)
            #expect(try fixture.readBytes(Self.path) == before)
            #expect(try await fixture.unmergedPaths() == [Self.path])
        }
    }

    @Test
    func acceptingYoursKeepsTheLatin1BytesExactly() async throws {
        try await withTempDir { dir in
            let fixture = try await latin1Conflict(in: dir)
            let model = try makeModel(dir)
            await model.load()

            let finished = await model.requestAcceptSide(.yours, window: nil)

            #expect(finished)
            #expect(try fixture.readBytes(Self.path) == Self.latin1Ours)
            #expect(try await fixture.unmergedPaths().isEmpty)
            #expect(try await fixture.indexMatchesWorktree(Self.path))
        }
    }

    @Test
    func acceptingTheirsKeepsTheLatin1BytesExactly() async throws {
        try await withTempDir { dir in
            let fixture = try await latin1Conflict(in: dir)
            let model = try makeModel(dir)
            await model.load()

            let finished = await model.requestAcceptSide(.theirs, window: nil)

            #expect(finished)
            #expect(try fixture.readBytes(Self.path) == Self.latin1Theirs)
            #expect(try await fixture.unmergedPaths().isEmpty)
            #expect(try await fixture.indexMatchesWorktree(Self.path))
        }
    }

    @Test
    func acceptingYoursDuringARebaseTakesTheRebasedCommitsThroughGit() async throws {
        try await withTempDir { dir in
            let fixture = try await GitMergeFixture.byteRebaseConflict(
                in: dir,
                path: Self.path,
                base: Self.latin1Base,
                main: Self.latin1Ours,
                feature: Self.latin1Theirs
            )
            let model = try makeModel(dir)
            await model.load()
            #expect(model.context?.swapsSides == true)

            let finished = await model.acceptSide(.yours)

            #expect(finished)
            #expect(try fixture.readBytes(Self.path) == Self.latin1Theirs)
            #expect(try await fixture.unmergedPaths().isEmpty)
        }
    }

    @Test
    func acceptingASideFailsWithoutTouchingTheFileWhileTheIndexIsLocked() async throws {
        try await withTempDir { dir in
            let fixture = try await latin1Conflict(in: dir)
            let model = try makeModel(dir)
            await model.load()
            let before = try fixture.readBytes(Self.path)
            try fixture.write(".git/index.lock", "")

            let finished = await model.acceptSide(.yours)

            #expect(finished == false)
            #expect(model.errorMessage?.isEmpty == false)
            #expect(model.errorMessage != Self.undecodableMessage)
            #expect(model.isSaving == false)
            #expect(try fixture.readBytes(Self.path) == before)
            #expect(try await fixture.unmergedPaths() == [Self.path])
        }
    }

    @Test
    func utf8FileWithAByteOrderMarkStaysMergeableAndRoundTripsExactly() async throws {
        try await withTempDir { dir in
            let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
            let fixture = try await GitMergeFixture.byteConflict(
                in: dir,
                path: Self.path,
                base: bom + GitMergeFixture.utf8Bytes("intro\nh\u{E9}llo\nend\n"),
                ours: bom + GitMergeFixture.utf8Bytes("intro\nh\u{E9}llo main\nend\n"),
                theirs: bom + GitMergeFixture.utf8Bytes("intro\nh\u{E9}llo feature\nend\n")
            )
            let model = try makeModel(dir)
            await model.load()
            let conflict = try #require(model.merge?.blocks.first { $0.kind == .conflict })

            #expect(model.isUndecodable == false)
            await model.requestResolve(conflict.id, with: .left, window: nil)
            let applied = await model.apply()

            #expect(applied)
            let expected = bom + GitMergeFixture.utf8Bytes("intro\nh\u{E9}llo main\nend\n")
            #expect(try fixture.readBytes(Self.path) == expected)
            #expect(try await fixture.unmergedPaths().isEmpty)
        }
    }
}
