import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite
struct GitLogViewModelTests {
    private func makeRepo(_ dir: URL) async throws -> (GitMergeFixture, SourceControlManager) {
        let fixture = try await GitMergeFixture.offMain {
            let fixture = try GitMergeFixture(root: dir)
            try fixture.write("a.txt", "a\n")
            try fixture.commit("initial")
            try fixture.run("checkout", "-q", "-b", "feature")
            try fixture.write("src/feature.txt", "f\n")
            try fixture.run("add", "-A")
            try fixture.run("commit", "-q", "-m", "Feature subject", "-m", "Feature body line")
            try fixture.run("checkout", "-q", "main")
            try fixture.write("a.txt", "main\n")
            try fixture.commit("Main change by author")
            return fixture
        }
        return (fixture, SourceControlManager(workspaceURL: dir, editorManager: EditorManager()))
    }

    @Test
    func loadShowsAllBranchesAndSelectsTheNewestCommit() async throws {
        try await withTempDir { dir in
            let (_, manager) = try await makeRepo(dir)
            let model = GitLogViewModel()
            await model.load(manager: manager)

            #expect(Set(model.commits.map(\.subject)) == ["initial", "Feature subject", "Main change by author"])
            #expect(model.graphRows.count == 3)
            #expect(model.laneCount == 2)
            #expect(model.errorMessage == nil)
            #expect(model.isLoading == false)
            #expect(model.selectedHash == model.commits.first?.hash)
            #expect(model.tabTitle == "Log")
        }
    }

    @Test
    func selectingACommitLoadsFullMessageAndChangedFiles() async throws {
        try await withTempDir { dir in
            let (_, manager) = try await makeRepo(dir)
            let model = GitLogViewModel()
            await model.load(manager: manager)
            let feature = try #require(model.commits.first { $0.subject == "Feature subject" })

            await model.select(hash: feature.hash)

            #expect(model.selectedCommit == feature)
            #expect(model.selectedMessage == "Feature subject\n\nFeature body line")
            #expect(model.selectedFiles.map(\.fileURL.lastPathComponent) == ["feature.txt"])
            #expect(model.selectedFiles.first?.status == .added)
        }
    }

    @Test
    func rootCommitListsItsFiles() async throws {
        try await withTempDir { dir in
            let (_, manager) = try await makeRepo(dir)
            let model = GitLogViewModel()
            await model.load(manager: manager)
            let root = try #require(model.commits.first { $0.subject == "initial" })

            await model.select(hash: root.hash)

            #expect(model.selectedFiles.map(\.fileURL.lastPathComponent) == ["a.txt"])
        }
    }

    @Test
    func clearingSelectionEmptiesDetails() async throws {
        try await withTempDir { dir in
            let (_, manager) = try await makeRepo(dir)
            let model = GitLogViewModel()
            await model.load(manager: manager)
            await model.select(hash: nil)

            #expect(model.selectedCommit == nil)
            #expect(model.selectedFiles.isEmpty)
            #expect(model.selectedMessage.isEmpty)
        }
    }

    @Test
    func branchFilterReloadsOnlyThatBranchAndRenamesTheTab() async throws {
        try await withTempDir { dir in
            let (_, manager) = try await makeRepo(dir)
            let model = GitLogViewModel()
            await model.load(manager: manager)

            await model.setBranchFilter(GitLogBranchFilter(ref: "feature", title: "feature"))

            #expect(model.commits.map(\.subject) == ["Feature subject", "initial"])
            #expect(model.tabTitle == "Log: feature")
            #expect(model.selectedCommit?.subject == "Feature subject")
            #expect(model.laneCount == 1)
        }
    }

    @Test
    func reloadKeepsTheSelectedCommit() async throws {
        try await withTempDir { dir in
            let (fixture, manager) = try await makeRepo(dir)
            let model = GitLogViewModel()
            await model.load(manager: manager)
            let root = try #require(model.commits.first { $0.subject == "initial" })
            await model.select(hash: root.hash)
            try fixture.write("b.txt", "b\n")
            try fixture.commit("Later")

            await model.load(manager: manager)

            #expect(model.commits.count == 4)
            #expect(model.selectedHash == root.hash)
        }
    }

    @Test
    func searchFiltersBySubjectAuthorAndHashPrefix() async throws {
        try await withTempDir { dir in
            let (_, manager) = try await makeRepo(dir)
            let model = GitLogViewModel()
            await model.load(manager: manager)
            let feature = try #require(model.commits.first { $0.subject == "Feature subject" })

            model.searchText = "  FEATURE "
            #expect(model.visibleCommits.map(\.subject) == ["Feature subject"])

            model.searchText = String(feature.hash.prefix(6))
            #expect(model.visibleCommits.map(\.hash) == [feature.hash])

            model.searchText = "merge"
            #expect(model.visibleCommits.count == 3)

            model.searchText = "nothing-matches"
            #expect(model.visibleCommits.isEmpty)

            model.searchText = ""
            #expect(model.visibleCommits.count == 3)
        }
    }

    @Test
    func nonRepositoryReportsAnErrorAndEmptyLog() async throws {
        try await withTempDir { dir in
            let model = GitLogViewModel()
            await model.load(manager: SourceControlManager(workspaceURL: dir, editorManager: EditorManager()))

            #expect(model.commits.isEmpty)
            #expect(model.graphRows.isEmpty)
            #expect(model.errorMessage?.isEmpty == false)
            #expect(model.selectedHash == nil)
        }
    }
}

@Suite
struct GitLogSmallModelTests {
    private let now = Date(timeIntervalSince1970: 1_000_000_000)

    static let relativeDateCases: [(Int, String)] = [
        (0, "just now"),
        (44, "just now"),
        (45, "1 minute ago"),
        (59, "1 minute ago"),
        (60, "1 minute ago"),
        (125, "2 minutes ago"),
        (3_599, "59 minutes ago"),
        (3_600, "1 hour ago"),
        (86_399, "23 hours ago"),
        (86_400, "1 day ago"),
        (2_505_600, "29 days ago"),
        (2_592_000, "1 month ago"),
        (31_017_600, "11 months ago"),
        (31_104_000, "1 year ago"),
        (69_120_000, "2 years ago")
    ]

    @Test(arguments: relativeDateCases)
    func relativeDate(secondsAgo: Int, expected: String) {
        let date = now.addingTimeInterval(-Double(secondsAgo))
        #expect(GitLogRelativeDate.string(for: date, now: now) == expected)
    }

    @Test
    func futureDatesReadAsJustNow() {
        #expect(GitLogRelativeDate.string(for: now.addingTimeInterval(600), now: now) == "just now")
    }

    @Test(arguments: [
        ("/repo/src/app/main.swift", "/repo", "src/app"),
        ("/repo/src/app/main.swift", "/repo/", "src/app"),
        ("/repo/main.swift", "/repo", ""),
        ("/elsewhere/main.swift", "/repo", ""),
        ("/repository/src/main.swift", "/repo", "")
    ])
    func changedFileDirectoryIsRelativeToTheRoot(path: String, root: String, expected: String) {
        let file = GitChangedFile(
            status: .modified,
            stagedStatus: .none,
            fileURL: URL(fileURLWithPath: path),
            originalFilename: nil
        )
        #expect(file.gitRelativeDirectory(from: URL(fileURLWithPath: root)) == expected)
    }

    @Test
    func commitFlagsMergesAndShortHash() {
        let commit = GitLogCommit(
            hash: "0123456789abcdef",
            parents: ["a", "b"],
            authorName: "Ann",
            authorEmail: "ann@example.com",
            date: now,
            refs: [GitLogRef(name: "main", kind: .branch)],
            subject: "Merge"
        )
        #expect(commit.isMerge)
        #expect(commit.shortHash == "01234567")
        #expect(commit.matches(graphText: "ann"))
        #expect(commit.matches(graphText: "0123"))
        #expect(commit.matches(graphText: "4567") == false)
        #expect(commit.refs.first?.id == "branch:main")
        #expect(GitLogBranchFilter.all.id == "HEAD")
    }
}
