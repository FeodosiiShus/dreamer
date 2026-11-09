import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct PartialsClientMiscDiffViewerTests {
    private static let root = URL(fileURLWithPath: "/tmp/partials-client-misc-diff", isDirectory: true)

    private func makeRepository(
        tracked: String,
        untracked: ProcessOutput
    ) -> DiffRepository {
        let (client, _) = ScmFakeGit.client(directory: Self.root) { invocation in
            ScmFakeGit.arguments(invocation).contains("ls-files") ? untracked : ScmFakeGit.ok(tracked)
        }
        return DiffRepository(gitClient: client, rootURL: Self.root)
    }

    @Test
    func trackedChangesAreListedWhenUntrackedFilesCannotBeEnumerated() async throws {
        let repository = makeRepository(
            tracked: "M\tb.txt\nD\ta.txt\n",
            untracked: ScmFakeGit.failure("fatal: ls-files failed")
        )

        let requests = try await repository.workingTreeRequests(against: "HEAD")

        #expect(requests.map(\.path) == ["a.txt", "b.txt"])
        #expect(requests.map(\.status) == [.deleted, .modified])
    }

    @Test
    func repeatedAndBlankEntriesProduceOneRequestPerPath() async throws {
        let repository = makeRepository(
            tracked: "M\ta.txt\nA\ta.txt\n",
            untracked: ScmFakeGit.ok("   \na.txt\nnew.txt\n  new.txt  \n")
        )

        let requests = try await repository.workingTreeRequests(against: "HEAD")

        #expect(requests.map(\.path) == ["a.txt", "new.txt"])
        #expect(requests.map(\.status) == [.modified, .untracked])
    }

    @Test
    func aViewModelWithoutFilesCountsNoDifferences() {
        let repository = makeRepository(tracked: "", untracked: ScmFakeGit.ok())
        let model = DiffViewerViewModel(repository: repository, mode: .workingTree(ref: "HEAD"), files: [])

        #expect(model.diff == nil)
        #expect(model.differenceCount == 0)
        #expect(model.differenceSummary.isEmpty)
    }
}
