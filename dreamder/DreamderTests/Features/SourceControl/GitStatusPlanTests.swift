import Foundation
import Testing
@testable import Dreamder

@Suite
struct GitStatusPlanTests {
    private static let repository = URL(filePath: "/repo/", directoryHint: .isDirectory)

    private func change(_ path: String, status: GitStatus, staged: GitStatus = .none) -> GitChangedFile {
        GitChangedFile(
            status: status,
            stagedStatus: staged,
            fileURL: URL(filePath: path, relativeTo: Self.repository),
            originalFilename: nil
        )
    }

    private func makePlan(_ files: [GitChangedFile]) -> GitStatusPlan {
        GitStatusPlan(changedFiles: files)
    }

    @Test
    func statusesAreKeyedByWorkspacePathWithTheUserFacingStatus() {
        let plan = makePlan([
            change("a.swift", status: .modified),
            change("b.swift", status: .none, staged: .added),
            change("dir/c.swift", status: .untracked)
        ])

        #expect(plan.statuses == [
            "/repo/a.swift": .modified,
            "/repo/b.swift": .added,
            "/repo/dir/c.swift": .untracked
        ])
        #expect(plan.untrackedDirectories.isEmpty)
    }

    @Test
    func untrackedDirectoryEntriesLoseTheirTrailingSlashAndAreRemembered() {
        let plan = makePlan([
            change("newdir/", status: .untracked),
            change("plain.txt", status: .untracked)
        ])

        #expect(plan.statuses["/repo/newdir"] == .untracked)
        #expect(plan.statuses["/repo/plain.txt"] == .untracked)
        #expect(plan.untrackedDirectories == ["/repo/newdir"])
    }

    @Test
    func descendantsOfUntrackedDirectoriesInheritTheUntrackedStatus() {
        let plan = makePlan([change("newdir/", status: .untracked), change("a.swift", status: .modified)])

        #expect(plan.status(forPath: "/repo/newdir") == .untracked)
        #expect(plan.status(forPath: "/repo/newdir/file.txt") == .untracked)
        #expect(plan.status(forPath: "/repo/newdir/deep/er/file.txt") == .untracked)
        #expect(plan.status(forPath: "/repo/a.swift") == .modified)
    }

    @Test
    func pathsOutsideTheChangesHaveNoStatus() {
        let plan = makePlan([change("newdir/", status: .untracked)])

        #expect(plan.status(forPath: "/repo/newdir2/file.txt") == nil)
        #expect(plan.status(forPath: "/repo/other.txt") == nil)
        #expect(plan.status(forPath: "/x") == nil)
        #expect(GitStatusPlan().status(forPath: "/repo/newdir/file.txt") == nil)
    }

    @Test
    func equalChangeListsProduceEqualPlans() {
        let files = [change("a.swift", status: .modified), change("dir/", status: .untracked)]

        #expect(makePlan(files) == makePlan(files))
        #expect(makePlan(files) != GitStatusPlan())
        #expect(GitStatusPlan() == GitStatusPlan())
    }
}
