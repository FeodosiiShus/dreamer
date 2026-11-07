import Foundation
import Testing
@testable import Dreamder

@Suite
struct BranchesCompareCommitListTests {
    @Test
    func parsesHashSubjectAuthorAndDate() {
        let commits = BranchesCompareCommit.list(from: "abc1234|Fix the bug|Ada Lovelace|2024-05-06")

        #expect(commits == [
            BranchesCompareCommit(hash: "abc1234", subject: "Fix the bug", author: "Ada Lovelace", date: "2024-05-06")
        ])
        #expect(commits.first?.id == "abc1234")
    }

    @Test
    func keepsGitOrderAcrossLines() {
        let output = "ccc|third|C|2024-01-03\nbbb|second|B|2024-01-02\naaa|first|A|2024-01-01\n"

        #expect(BranchesCompareCommit.list(from: output).map(\.hash) == ["ccc", "bbb", "aaa"])
    }

    @Test
    func trailingNewlineDoesNotProduceAnExtraCommit() {
        let withNewline = BranchesCompareCommit.list(from: "aaa|one|A|2024-01-01\n")
        let withoutNewline = BranchesCompareCommit.list(from: "aaa|one|A|2024-01-01")

        #expect(withNewline == withoutNewline)
        #expect(withNewline.count == 1)
    }

    @Test
    func emptyOutputYieldsNoCommits() {
        #expect(BranchesCompareCommit.list(from: "").isEmpty)
        #expect(BranchesCompareCommit.list(from: "\n\n").isEmpty)
    }

    @Test
    func whitespaceOnlyLinesAreSkipped() {
        let output = "   \naaa|one|A|2024-01-01\n\t\n \t \nbbb|two|B|2024-01-02"

        #expect(BranchesCompareCommit.list(from: output).map(\.hash) == ["aaa", "bbb"])
    }

    @Test
    func linesWithFewerThanFourFieldsAreSkipped() {
        let output = [
            "aaa",
            "aaa|only subject",
            "aaa|subject|author",
            "bbb|two|B|2024-01-02"
        ].joined(separator: "\n")

        #expect(BranchesCompareCommit.list(from: output).map(\.hash) == ["bbb"])
    }

    @Test
    func linesWithAnEmptyHashAreSkipped() {
        let output = "|subject|author|2024-01-01\nbbb|two|B|2024-01-02"

        #expect(BranchesCompareCommit.list(from: output).map(\.hash) == ["bbb"])
    }

    @Test
    func emptySubjectAuthorAndDateAreKept() {
        let commits = BranchesCompareCommit.list(from: "aaa|||")

        #expect(commits == [BranchesCompareCommit(hash: "aaa", subject: "", author: "", date: "")])
    }

    @Test
    func subjectContainingPipesKeepsAuthorAndDateIntact() {
        let commits = BranchesCompareCommit.list(from: "aaa|fix a|b and c||d|Ada|2024-05-06")

        #expect(commits.count == 1)
        #expect(commits.first?.subject == "fix a|b and c||d")
        #expect(commits.first?.author == "Ada")
        #expect(commits.first?.date == "2024-05-06")
    }

    @Test
    func subjectWithASinglePipeIsNotSplit() {
        let commits = BranchesCompareCommit.list(from: "aaa|left|right|Ada|2024-05-06")

        #expect(commits.first?.subject == "left|right")
        #expect(commits.first?.author == "Ada")
        #expect(commits.first?.date == "2024-05-06")
    }

    @Test
    func crlfLineEndingsDoNotLeakIntoFields() {
        let output = "aaa|one|A|2024-01-01\r\nbbb|two|B|2024-01-02\r\n"

        let commits = BranchesCompareCommit.list(from: output)

        #expect(commits.map(\.hash) == ["aaa", "bbb"])
        #expect(commits.map(\.date) == ["2024-01-01", "2024-01-02"])
    }

    @Test
    func surroundingSpacesOfALineAreTrimmedButInnerSpacesStay() {
        let commits = BranchesCompareCommit.list(from: "  aaa| spaced subject |Ada Lovelace|2024-01-01  ")

        #expect(commits.first?.hash == "aaa")
        #expect(commits.first?.subject == " spaced subject ")
        #expect(commits.first?.author == "Ada Lovelace")
        #expect(commits.first?.date == "2024-01-01")
    }

    @Test
    func commitsAreIdentifiedByHash() {
        let first = BranchesCompareCommit(hash: "aaa", subject: "one", author: "A", date: "d")
        let second = BranchesCompareCommit(hash: "bbb", subject: "one", author: "A", date: "d")

        #expect(first.id != second.id)
        #expect(Set([first, second, first]).count == 2)
    }
}

@MainActor
@Suite
struct BranchesCompareViewModelTests {
    private nonisolated static func mutate(
        _ fixture: GitMergeFixture,
        _ body: @escaping @Sendable (GitMergeFixture) throws -> Void
    ) async throws {
        _ = try await GitMergeFixture.offMain {
            try body(fixture)
            return fixture
        }
    }

    private func makeDivergedRepository(_ dir: URL) async throws -> (GitMergeFixture, SourceControlManager) {
        let fixture = try await GitMergeFixture.offMain {
            let fixture = try GitMergeFixture(root: dir)
            try fixture.write("a.txt", "base\n")
            try fixture.commit("base commit")
            try fixture.run("checkout", "-q", "-b", "feature")
            try fixture.write("feature.txt", "one\n")
            try fixture.commit("feature one")
            try fixture.write("feature.txt", "two\n")
            try fixture.commit("feature two")
            try fixture.run("checkout", "-q", "main")
            try fixture.write("main.txt", "main\n")
            try fixture.commit("main only")
            return fixture
        }
        return (fixture, SourceControlManager(workspaceURL: dir, editorManager: EditorManager()))
    }

    @Test
    func titleNamesBothBranches() throws {
        try withTempDir { dir in
            let manager = SourceControlManager(workspaceURL: dir, editorManager: EditorManager())
            let model = BranchesCompareViewModel(manager: manager, branch: "feature/x", current: "main")

            #expect(model.title == "Comparing feature/x with main")
        }
    }

    @Test
    func startsLoadingWithoutCommitsOrError() throws {
        try withTempDir { dir in
            let manager = SourceControlManager(workspaceURL: dir, editorManager: EditorManager())
            let model = BranchesCompareViewModel(manager: manager, branch: "feature", current: "main")

            #expect(model.isLoading)
            #expect(model.branchOnly.isEmpty)
            #expect(model.currentOnly.isEmpty)
            #expect(model.errorMessage == nil)
        }
    }

    @Test
    func loadSplitsCommitsIntoBranchOnlyAndCurrentOnlyNewestFirst() async throws {
        try await withTempDir { dir in
            let (fixture, manager) = try await makeDivergedRepository(dir)
            let model = BranchesCompareViewModel(manager: manager, branch: "feature", current: "main")

            await model.load()

            #expect(model.branchOnly.map(\.subject) == ["feature two", "feature one"])
            #expect(model.currentOnly.map(\.subject) == ["main only"])
            #expect(model.errorMessage == nil)
            #expect(model.isLoading == false)

            let featureHead = try fixture.run("rev-parse", "feature").trimmingCharacters(in: .whitespacesAndNewlines)
            let mainHead = try fixture.run("rev-parse", "main").trimmingCharacters(in: .whitespacesAndNewlines)
            let branchOnlyHash = try #require(model.branchOnly.first?.hash)
            let currentOnlyHash = try #require(model.currentOnly.first?.hash)
            #expect(featureHead.hasPrefix(branchOnlyHash))
            #expect(mainHead.hasPrefix(currentOnlyHash))
        }
    }

    @Test
    func loadReportsAuthorAndShortDate() async throws {
        try await withTempDir { dir in
            let (fixture, manager) = try await makeDivergedRepository(dir)
            let model = BranchesCompareViewModel(manager: manager, branch: "feature", current: "main")

            await model.load()

            let expectedDate = try fixture
                .run("log", "-1", "--format=%ad", "--date=short", "feature")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let commit = try #require(model.branchOnly.first)
            #expect(commit.author == "Merge")
            #expect(commit.date == expectedDate)
        }
    }

    @Test
    func swappingBranchAndCurrentSwapsTheSides() async throws {
        try await withTempDir { dir in
            let (_, manager) = try await makeDivergedRepository(dir)
            let model = BranchesCompareViewModel(manager: manager, branch: "main", current: "feature")

            await model.load()

            #expect(model.branchOnly.map(\.subject) == ["main only"])
            #expect(model.currentOnly.map(\.subject) == ["feature two", "feature one"])
        }
    }

    @Test
    func subjectsContainingPipesSurviveTheRoundTripThroughGit() async throws {
        try await withTempDir { dir in
            let (fixture, manager) = try await makeDivergedRepository(dir)
            try await Self.mutate(fixture) { fixture in
                try fixture.run("checkout", "-q", "feature")
                try fixture.write("pipe.txt", "p\n")
                try fixture.commit("fix a|b handling")
                try fixture.run("checkout", "-q", "main")
            }
            let model = BranchesCompareViewModel(manager: manager, branch: "feature", current: "main")

            await model.load()

            let commit = try #require(model.branchOnly.first)
            #expect(commit.subject == "fix a|b handling")
            #expect(commit.author == "Merge")
        }
    }

    @Test
    func identicalBranchesHaveNoDifferencesAndNoError() async throws {
        try await withTempDir { dir in
            let (_, manager) = try await makeDivergedRepository(dir)
            let model = BranchesCompareViewModel(manager: manager, branch: "main", current: "main")

            await model.load()

            #expect(model.branchOnly.isEmpty)
            #expect(model.currentOnly.isEmpty)
            #expect(model.errorMessage == nil)
            #expect(model.isLoading == false)
        }
    }

    @Test
    func loadingOutsideARepositoryReportsTheErrorAndStopsLoading() async throws {
        try await withTempDir { dir in
            let manager = SourceControlManager(workspaceURL: dir, editorManager: EditorManager())
            let model = BranchesCompareViewModel(manager: manager, branch: "feature", current: "main")

            await model.load()

            #expect(model.errorMessage == "Not a git repository")
            #expect(model.isLoading == false)
            #expect(model.branchOnly.isEmpty)
            #expect(model.currentOnly.isEmpty)
        }
    }

    @Test
    func unknownBranchReportsAnErrorAndLaterLoadClearsIt() async throws {
        try await withTempDir { dir in
            let (fixture, manager) = try await makeDivergedRepository(dir)
            let model = BranchesCompareViewModel(manager: manager, branch: "later", current: "main")

            await model.load()

            let message = try #require(model.errorMessage)
            #expect(message.isEmpty == false)
            #expect(model.isLoading == false)
            #expect(model.branchOnly.isEmpty)

            try await Self.mutate(fixture) { fixture in
                try fixture.run("checkout", "-q", "-b", "later")
                try fixture.write("later.txt", "l\n")
                try fixture.commit("later commit")
                try fixture.run("checkout", "-q", "main")
            }
            await model.load()

            #expect(model.errorMessage == nil)
            #expect(model.branchOnly.map(\.subject) == ["later commit"])
            #expect(model.currentOnly.isEmpty)
            #expect(model.isLoading == false)
        }
    }
}
