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

            await model.setBranchFilter(.fromBranch("feature"))

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
    func textFilterMatchesMessagesAndHashFilterMatchesPrefixes() async throws {
        try await withTempDir { dir in
            let (_, manager) = try await makeRepo(dir)
            let model = GitLogViewModel()
            await model.load(manager: manager)
            let feature = try #require(model.commits.first { $0.subject == "Feature subject" })

            await model.setFilters(model.filters.settingText("  FEATURE ", isRegexpAllowed: false, isMatchCase: false))
            #expect(model.visibleCommits.map(\.subject) == ["Feature subject"])
            #expect(model.graphRows.count == 1)

            await model.setFilters(model.filters.settingText("FEATURE", isRegexpAllowed: false, isMatchCase: true))
            #expect(model.visibleCommits.isEmpty)

            await model.setFilters(model.filters.settingText(String(feature.hash.prefix(8)), isRegexpAllowed: false, isMatchCase: false))
            #expect(model.visibleCommits.map(\.hash) == [feature.hash])

            await model.setFilters(model.filters.settingText("nothing-matches", isRegexpAllowed: false, isMatchCase: false))
            #expect(model.visibleCommits.isEmpty)

            await model.setFilters(model.filters.settingText("", isRegexpAllowed: false, isMatchCase: false))
            #expect(model.visibleCommits.count == 3)
            #expect(model.graphRows.count == 3)
        }
    }

    @Test
    func userAndMergeFiltersApplyInMemory() async throws {
        try await withTempDir { dir in
            let (_, manager) = try await makeRepo(dir)
            let model = GitLogViewModel()
            await model.load(manager: manager)
            let author = try #require(model.commits.first)

            await model.setFilters(model.filters.settingUserNames([author.authorName]))
            #expect(model.visibleCommits.count == 3)

            await model.setFilters(model.filters.settingUserNames(["nobody"]))
            #expect(model.visibleCommits.isEmpty)

            await model.setFilters(GitLogFilterCollection().settingParent(.onlyMerges))
            #expect(model.visibleCommits.isEmpty)

            await model.setFilters(GitLogFilterCollection().settingParent(.noMerges))
            #expect(model.visibleCommits.count == 3)
        }
    }

    @Test
    func pathFilterReloadsFromGitAndKeepsTheGraphConsistent() async throws {
        try await withTempDir { dir in
            let (_, manager) = try await makeRepo(dir)
            let model = GitLogViewModel()
            await model.load(manager: manager)

            await model.setFilters(model.filters.settingPaths(from: "src"))

            #expect(model.visibleCommits.map(\.subject) == ["Feature subject"])
            #expect(model.graphRows.count == 1)
        }
    }

    private func makeManager(_ dir: URL, build: @escaping @Sendable (GitMergeFixture) throws -> Void) async throws -> SourceControlManager {
        _ = try await GitMergeFixture.offMain {
            let fixture = try GitMergeFixture(root: dir)
            try build(fixture)
            return fixture
        }
        return SourceControlManager(workspaceURL: dir, editorManager: EditorManager())
    }

    private nonisolated static func buildLinearHistory(_ fixture: GitMergeFixture) throws {
        for index in 1...5 {
            try fixture.write("f\(index).txt", "\(index)\n")
            try fixture.commit("c\(index)")
        }
    }

    @Test
    func firstParentOptionHidesMergedSideBranchCommitsAndRestoresThem() async throws {
        try await withTempDir { dir in
            let manager = try await makeManager(dir) { fixture in
                try fixture.write("a.txt", "a\n")
                try fixture.commit("initial")
                try fixture.run("checkout", "-q", "-b", "side")
                try fixture.write("side.txt", "s\n")
                try fixture.commit("side work")
                try fixture.run("checkout", "-q", "main")
                try fixture.write("main.txt", "m\n")
                try fixture.commit("main work")
                try fixture.run("merge", "-q", "--no-ff", "-m", "merge side", "side")
                try fixture.run("branch", "-q", "-d", "side")
            }
            let model = GitLogViewModel()
            await model.load(manager: manager)
            #expect(Set(model.visibleCommits.map(\.subject)) == ["merge side", "main work", "side work", "initial"])

            await model.setFirstParent(true)
            #expect(Set(model.visibleCommits.map(\.subject)) == ["merge side", "main work", "initial"])
            #expect(model.graphRows.count == 3)
            #expect(model.options.firstParent)

            await model.setFirstParent(true)
            #expect(model.visibleCommits.count == 3)

            await model.setFirstParent(false)
            #expect(Set(model.visibleCommits.map(\.subject)) == ["merge side", "main work", "side work", "initial"])
            #expect(model.graphRows.count == 4)
        }
    }

    @Test
    func meUserFilterResolvesTheConfiguredUserAndKeepsOnlyTheirCommits() async throws {
        try await withTempDir { dir in
            let manager = try await makeManager(dir) { fixture in
                try fixture.write("a.txt", "a\n")
                try fixture.commit("mine one")
                try fixture.write("b.txt", "b\n")
                try fixture.commit("mine two")
                try fixture.write("c.txt", "c\n")
                try fixture.run("add", "-A")
                try fixture.run(
                    "-c", "user.name=Other Person", "-c", "user.email=other@dreamder.test",
                    "commit", "-qm", "by other"
                )
            }
            let model = GitLogViewModel()
            await model.load(manager: manager)
            #expect(model.visibleCommits.count == 3)
            #expect(model.currentUser == nil)

            await model.setFilters(GitLogFilterCollection().settingUserNames([GitLogUserFilter.me]))

            #expect(model.currentUser == GitLogUser(name: "Merge", email: "merge@dreamder.test"))
            #expect(Set(model.visibleCommits.map(\.subject)) == ["mine one", "mine two"])
            #expect(model.graphRows.count == 2)
        }
    }

    @Test
    func textFilterStaysInMemoryWhenTheHistoryFitsTheLoadLimit() async throws {
        try await withTempDir { dir in
            let manager = try await makeManager(dir, build: Self.buildLinearHistory)
            let model = GitLogViewModel()
            await model.load(manager: manager)

            await model.setFilters(GitLogFilterCollection().settingText("c2", isRegexpAllowed: false, isMatchCase: false))

            #expect(model.detailsAppliedByGit == false)
            #expect(model.commits.count == 5)
            #expect(model.visibleCommits.map(\.subject) == ["c2"])
        }
    }

    @Test
    func textFilterRefetchesFromGitWhenTheHistoryExceedsTheLoadLimit() async throws {
        try await withTempDir { dir in
            let manager = try await makeManager(dir, build: Self.buildLinearHistory)
            let model = GitLogViewModel(loadLimit: 3)
            await model.load(manager: manager)
            #expect(model.commits.count == 3)
            #expect(model.detailsAppliedByGit == false)

            await model.setFilters(GitLogFilterCollection().settingText("c2", isRegexpAllowed: false, isMatchCase: false))
            #expect(model.detailsAppliedByGit)
            #expect(model.visibleCommits.map(\.subject) == ["c2"])

            await model.setFilters(GitLogFilterCollection())
            #expect(model.detailsAppliedByGit == false)
            #expect(model.commits.count == 3)
            #expect(model.visibleCommits.map(\.subject) == ["c5", "c4", "c3"])
        }
    }

    @Test
    func filtersSetBeforeTheFirstLoadAreAppliedByGitWhenTheLogIsTruncated() async throws {
        try await withTempDir { dir in
            let manager = try await makeManager(dir, build: Self.buildLinearHistory)
            let model = GitLogViewModel(loadLimit: 3)
            await model.setFilters(GitLogFilterCollection().settingText("c2", isRegexpAllowed: false, isMatchCase: false))
            #expect(model.commits.isEmpty)

            await model.load(manager: manager)

            #expect(model.detailsAppliedByGit)
            #expect(model.visibleCommits.map(\.subject) == ["c2"])
            #expect(model.selectedHash == model.visibleCommits.first?.hash)
        }
    }

    @Test
    func selectingACommitWithoutChangedFilesLeavesTheListEmpty() async throws {
        try await withTempDir { dir in
            let manager = try await makeManager(dir) { fixture in
                try fixture.write("a.txt", "a\n")
                try fixture.commit("initial")
                try fixture.run("commit", "-q", "--allow-empty", "-m", "empty commit")
            }
            let model = GitLogViewModel()
            await model.load(manager: manager)

            #expect(model.selectedCommit?.subject == "empty commit")
            #expect(model.selectedFiles.isEmpty)
            #expect(model.selectedMessage == "empty commit")
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
        #expect(commit.message == "Merge")
        #expect(commit.commitDate == now)
        #expect(commit.refs.first?.id == "branch:main")
        #expect(GitLogBranchFilter.fromBranch("main").displayText == "main")
    }
}
