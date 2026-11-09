import AppKit
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
@Suite(.uiGate)
struct BranchesCompareViewModelTests {
    private func makeDivergedRepository(_ dir: URL) async throws -> (GitMergeFixture, SourceControlManager) {
        let fixture = try await GitMergeFixture(root: dir)
        try fixture.write("a.txt", "base\n")
        try await fixture.commit("base commit")
        try await fixture.run("checkout", "-q", "-b", "feature")
        try fixture.write("feature.txt", "one\n")
        try await fixture.commit("feature one")
        try fixture.write("feature.txt", "two\n")
        try await fixture.commit("feature two")
        try await fixture.run("checkout", "-q", "main")
        try fixture.write("main.txt", "main\n")
        try await fixture.commit("main only")
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

            let featureHead = try await fixture.run("rev-parse", "feature").trimmingCharacters(in: .whitespacesAndNewlines)
            let mainHead = try await fixture.run("rev-parse", "main").trimmingCharacters(in: .whitespacesAndNewlines)
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

            let expectedDate = try await fixture
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
            try await fixture.run("checkout", "-q", "feature")
            try fixture.write("pipe.txt", "p\n")
            try await fixture.commit("fix a|b handling")
            try await fixture.run("checkout", "-q", "main")
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

            try await fixture.run("checkout", "-q", "-b", "later")
            try fixture.write("later.txt", "l\n")
            try await fixture.commit("later commit")
            try await fixture.run("checkout", "-q", "main")
            await model.load()

            #expect(model.errorMessage == nil)
            #expect(model.branchOnly.map(\.subject) == ["later commit"])
            #expect(model.currentOnly.isEmpty)
            #expect(model.isLoading == false)
        }
    }

    @Test
    func cancelledLoadReportsTheSystemDescriptionOfTheError() async throws {
        try await withTempDir { dir in
            let manager = SourceControlManager(workspaceURL: dir, editorManager: EditorManager())
            let model = BranchesCompareViewModel(manager: manager, branch: "feature", current: "main")

            let load = Task { @MainActor in await model.load() }
            load.cancel()
            await load.value

            #expect(model.errorMessage == CancellationError().localizedDescription)
            #expect(model.isLoading == false)
            #expect(model.branchOnly.isEmpty)
            #expect(model.currentOnly.isEmpty)
        }
    }
}

extension BranchesCompareViewModelTests {
    @Test
    func hostedViewLoadsTheDivergedCommitsOfBothSides() async throws {
        try await withTempDir { dir in
            let (_, manager) = try await makeDivergedRepository(dir)
            let model = BranchesCompareViewModel(manager: manager, branch: "feature", current: "main")
            let hosted = HostedViewFixture.host { BranchesCompareView(model: model) }
            defer { hosted.close() }

            try await eventually { model.isLoading == false }
            try await hosted.settle()

            #expect(model.branchOnly.map(\.subject) == ["feature two", "feature one"])
            #expect(model.currentOnly.map(\.subject) == ["main only"])
            #expect(model.errorMessage == nil)
        }
    }

    @Test
    func hostedViewOfIdenticalBranchesHasNothingToList() async throws {
        try await withTempDir { dir in
            let (_, manager) = try await makeDivergedRepository(dir)
            let model = BranchesCompareViewModel(manager: manager, branch: "main", current: "main")
            let hosted = HostedViewFixture.host { BranchesCompareView(model: model) }
            defer { hosted.close() }

            try await eventually { model.isLoading == false }
            try await hosted.settle()

            #expect(model.branchOnly.isEmpty)
            #expect(model.currentOnly.isEmpty)
            #expect(model.errorMessage == nil)
        }
    }

    @Test
    func hostedViewOutsideARepositoryKeepsTheErrorAndNoCommits() async throws {
        try await withTempDir { dir in
            let manager = SourceControlManager(workspaceURL: dir, editorManager: EditorManager())
            let model = BranchesCompareViewModel(manager: manager, branch: "feature", current: "main")
            let hosted = HostedViewFixture.host { BranchesCompareView(model: model) }
            defer { hosted.close() }

            try await eventually { model.isLoading == false }
            try await hosted.settle()

            #expect(model.errorMessage == "Not a git repository")
            #expect(model.branchOnly.isEmpty)
            #expect(model.currentOnly.isEmpty)
        }
    }

    @Test
    func hostedViewRendersTheLoadingStateBeforeTheCommitsArrive() async throws {
        try await withTempDir { dir in
            let (_, manager) = try await makeDivergedRepository(dir)
            let model = BranchesCompareViewModel(manager: manager, branch: "feature", current: "main")
            let hosted = HostedViewFixture.host { BranchesCompareView(model: model) }
            defer { hosted.close() }

            hosted.layout()
            #expect(model.isLoading)
            #expect(model.branchOnly.isEmpty)

            try await eventually { model.isLoading == false }
            try await hosted.settle()
            #expect(model.branchOnly.count == 2)
        }
    }
}

@MainActor
@Suite(.serialized, .uiGate)
struct BranchesCompareWindowTests {
    private func makeController(
        in dir: URL,
        branch: String = "feature",
        current: String = "main"
    ) -> BranchesCompareWindowController {
        let manager = SourceControlManager(workspaceURL: dir, editorManager: EditorManager())
        let model = BranchesCompareViewModel(manager: manager, branch: branch, current: current)
        return BranchesCompareWindowController(model: model)
    }

    private func visibleWindows(titled title: String) -> [NSWindow] {
        NSApp.windows.filter { $0.title == title && $0.isVisible }
    }

    @Test
    func windowIsTitledAfterTheComparisonAndStyledDark() throws {
        try withTempDir { dir in
            let controller = makeController(in: dir, branch: "feature/x", current: "main")
            let window = try #require(controller.window)

            #expect(window.title == "Comparing feature/x with main")
            #expect(window.delegate === controller)
            #expect(window.appearance?.name == .darkAqua)
            #expect(window.isReleasedWhenClosed == false)
            #expect(window.styleMask.contains(.resizable))
            #expect(window.styleMask.contains(.closable))
        }
    }

    @Test
    func closingTheWindowNotifiesTheOwnerOnce() throws {
        try withTempDir { dir in
            let controller = makeController(in: dir)
            let window = try #require(controller.window)
            var closed = 0
            controller.onClose = { closed += 1 }
            controller.showWindow(nil)

            window.close()

            #expect(closed == 1)
        }
    }

    @Test
    func placeCentersTheWindowOnItsParent() throws {
        try withTempDir { dir in
            let controller = makeController(in: dir)
            let window = try #require(controller.window)
            let parent = NSWindow(
                contentRect: NSRect(x: 300, y: 400, width: 1000, height: 700),
                styleMask: [.titled],
                backing: .buffered,
                defer: false
            )
            parent.isReleasedWhenClosed = false

            controller.place(relativeTo: parent)

            #expect(abs(window.frame.midX - parent.frame.midX) < 1)
            #expect(abs(window.frame.midY - parent.frame.midY) < 1)
        }
    }

    @Test
    func placeWithoutAParentCentersTheWindowOnTheMainScreen() throws {
        guard let screen = NSScreen.main else { return }
        try withTempDir { dir in
            let controller = makeController(in: dir)
            let window = try #require(controller.window)

            controller.place(relativeTo: nil)

            #expect(abs(window.frame.midX - screen.visibleFrame.midX) < 1)
            #expect(abs(window.frame.midY - screen.visibleFrame.midY) < 1)
        }
    }

    @Test
    func presenterKeepsOneWindowPerComparisonAndForgetsClosedOnes() throws {
        try withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let suffix = UUID().uuidString
            let first = "feature-\(suffix)"
            let second = "release-\(suffix)"
            let firstTitle = "Comparing \(first) with main"
            let secondTitle = "Comparing \(second) with main"
            defer {
                for window in visibleWindows(titled: firstTitle) + visibleWindows(titled: secondTitle) {
                    window.close()
                }
            }

            BranchesComparePresenter.show(workspace: workspace, branch: first, current: "main")
            let opened = try #require(visibleWindows(titled: firstTitle).first)
            #expect(visibleWindows(titled: firstTitle).count == 1)

            BranchesComparePresenter.show(workspace: workspace, branch: first, current: "main")
            #expect(visibleWindows(titled: firstTitle).count == 1)
            #expect(visibleWindows(titled: firstTitle).first === opened)

            BranchesComparePresenter.show(workspace: workspace, branch: second, current: "main")
            #expect(visibleWindows(titled: secondTitle).count == 1)
            #expect(visibleWindows(titled: firstTitle).count == 1)

            opened.close()
            #expect(visibleWindows(titled: firstTitle).isEmpty)

            BranchesComparePresenter.show(workspace: workspace, branch: first, current: "main")
            let reopened = try #require(visibleWindows(titled: firstTitle).first)
            #expect(reopened !== opened)
        }
    }

    @Test
    func presenterDoesNothingWithoutASourceControlManager() throws {
        try withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            workspace.sourceControlManager = nil
            let branch = "orphan-\(UUID().uuidString)"

            BranchesComparePresenter.show(workspace: workspace, branch: branch, current: "main")

            #expect(visibleWindows(titled: "Comparing \(branch) with main").isEmpty)
        }
    }

    @Test
    func controllerCannotBeDecoded() throws {
        let data = try NSKeyedArchiver.archivedData(withRootObject: NSString(string: "x"), requiringSecureCoding: false)
        let decoder = try NSKeyedUnarchiver(forReadingFrom: data)

        #expect(BranchesCompareWindowController(coder: decoder) == nil)
    }
}
