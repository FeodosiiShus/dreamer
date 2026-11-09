import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct ScmModelsCoverage {
    private func branch(_ name: String, long: String, upstream: String? = nil) -> GitBranch {
        GitBranch(name: name, longName: long, upstream: upstream, ahead: 0, behind: 0)
    }

    @Test
    func branchesKnowWhetherTheyAreLocalOrRemote() {
        let local = branch("main", long: "refs/heads/main")
        let remote = branch("origin/main", long: "refs/remotes/origin/main")
        let other = branch("v1", long: "refs/tags/v1")

        #expect(local.isLocal)
        #expect(local.isRemote == false)
        #expect(remote.isRemote)
        #expect(remote.isLocal == false)
        #expect(other.isLocal == false)
        #expect(other.isRemote == false)
        #expect(local.id == "refs/heads/main")
        #expect(Set([local, local, remote]).count == 2)
    }

    @Test
    func groupsNestOnlyWhenTheFirstBranchLivesUnderTheirName() {
        let nested = GitBranchesGroup(name: "feature", branches: [branch("feature/a", long: "refs/heads/feature/a")])
        let flat = GitBranchesGroup(name: "feature", branches: [branch("main", long: "refs/heads/main")])
        let empty = GitBranchesGroup(name: "feature", branches: [])

        #expect(nested.shouldNest)
        #expect(flat.shouldNest == false)
        #expect(empty.shouldNest == false)

        var grown = empty
        grown.branches.append(branch("feature/b", long: "refs/heads/feature/b"))
        #expect(grown.shouldNest)
        #expect(grown != empty)
    }

    @Test
    func changedFilesExposeIdentityStatusAndWorkspaceKey() {
        let url = URL(fileURLWithPath: "/repo/dir/a b.txt")
        let unstaged = GitChangedFile(status: .modified, stagedStatus: .none, fileURL: url, originalFilename: nil)
        let staged = GitChangedFile(status: .none, stagedStatus: .added, fileURL: url, originalFilename: nil)
        let both = GitChangedFile(status: .modified, stagedStatus: .added, fileURL: url, originalFilename: "old.txt")

        #expect(unstaged.id == url.relativePath)
        #expect(unstaged.ceFileKey == "/repo/dir/a b.txt")
        #expect(unstaged.isStaged == false)
        #expect(staged.isStaged)
        #expect(unstaged.anyStatus() == .modified)
        #expect(staged.anyStatus() == .added)
        #expect(both.anyStatus() == .modified)
        #expect(Set([unstaged, staged, both]).count == 3)
        #expect(unstaged.hashValue == staged.hashValue)
    }

    @Test
    func statusDescriptionsAreTheShortLetters() {
        let expected: [(GitStatus, String, String)] = [
            (.none, ".", ""),
            (.modified, "M", "M"),
            (.untracked, "?", "U"),
            (.fileTypeChange, "T", "T"),
            (.added, "A", "A"),
            (.deleted, "D", "D"),
            (.renamed, "R", "R"),
            (.copied, "C", "C"),
            (.unmerged, "U", "U")
        ]
        for (status, raw, description) in expected {
            #expect(status.rawValue == raw)
            #expect(status.description == description)
            #expect(GitStatus(rawValue: raw) == status)
        }
        #expect(GitStatus(rawValue: "Z") == nil)
    }

    @Test
    func statusRoundTripsThroughCodable() throws {
        let data = try JSONEncoder().encode([GitStatus.modified, GitStatus.untracked])
        #expect(try JSONDecoder().decode([GitStatus].self, from: data) == [.modified, .untracked])
    }

    private func commit(remote: String?) -> GitCommit {
        GitCommit(
            hash: "abc",
            commitHash: "abcdef",
            message: "m",
            author: "a",
            authorEmail: "a@x",
            committer: "c",
            committerEmail: "c@x",
            body: "",
            refs: [],
            tag: "",
            remoteURL: remote.flatMap { URL(string: $0) },
            date: Date(timeIntervalSince1970: 0)
        )
    }

    @Test
    func commitsAreIdentifiedByTheirGeneratedIdentifier() {
        let first = commit(remote: nil)
        let second = commit(remote: nil)
        #expect(first.id != second.id)
        #expect(first == first)
        #expect(first != second)
        #expect(Set([first, second]).count == 2)
    }
}
