import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct GitLogFilterBarCoverageTests {
    private let after = Date(timeIntervalSince1970: 1_700_000_000)
    private let before = Date(timeIntervalSince1970: 1_710_000_000)

    private func makeManager(_ dir: URL) -> SourceControlManager {
        SourceControlManager(workspaceURL: dir, editorManager: EditorManager())
    }

    private func host<Content: View>(
        _ manager: SourceControlManager,
        size: NSSize = NSSize(width: 420, height: 340),
        @ViewBuilder _ content: () -> Content
    ) -> HostedView {
        let view = content()
        return HostedViewFixture.host(size: size) {
            view.environment(manager)
        }
    }

    private func localBranch(_ name: String) -> GitBranch {
        GitBranch(name: name, longName: "refs/heads/" + name, upstream: nil, ahead: 0, behind: 0)
    }

    private func remoteBranch(_ remote: String, _ name: String) -> GitBranch {
        GitBranch(name: name, longName: "refs/remotes/\(remote)/\(name)", upstream: nil, ahead: 0, behind: 0)
    }

    private func appliedPreset(_ preset: GitLogDatePreset, in viewModel: GitLogViewModel) -> Bool {
        guard let date = viewModel.filters.date, date.before == nil, let appliedAfter = date.after else { return false }
        return abs(appliedAfter.timeIntervalSinceNow + preset.interval) < 5
    }

    @Test
    func barRendersEveryChipStateAndTheOptionsMenu() async throws {
        try await withTempDir { dir in
            let manager = makeManager(dir)
            let viewModel = GitLogViewModel()
            let model = GitLogFilterBarModel(viewModel: viewModel, debounce: .milliseconds(5))
            let hosted = host(manager) { GitLogFilterBar(viewModel: viewModel, model: model) }
            defer { hosted.close() }
            try await hosted.settle(.milliseconds(60))
            #expect(hosted.renders())
            let empty = hosted.snapshot()

            await viewModel.setFilters(GitLogFilterCollection(branch: GitLogBranchFilter()))
            try await hosted.settle(.milliseconds(60))

            await viewModel.setFilters(
                GitLogFilterCollection(
                    branch: .fromBranch("feature"),
                    user: GitLogUserFilter(userNames: [GitLogUserFilter.me, "alice"]),
                    date: GitLogDateFilter(after: after, before: before),
                    structure: GitLogStructureFilter(paths: ["src", "docs"])
                )
            )
            try await hosted.settle(.milliseconds(60))
            #expect(hosted.renders())
            #expect(HostedView.pixelsDiffer(empty, hosted.snapshot()))

            model.text = "needle"
            try await hosted.settle(.milliseconds(60))
            #expect(hosted.renders())
        }
    }

    @Test
    func defaultInitialiserCreatesItsOwnModelAndSettlesTheDebouncedTask() async throws {
        try await withTempDir { dir in
            let manager = makeManager(dir)
            let viewModel = GitLogViewModel()
            let hosted = host(manager) { GitLogFilterBar(viewModel: viewModel) }
            defer { hosted.close() }
            try await hosted.settle(.milliseconds(400))
            #expect(hosted.renders())
            #expect(viewModel.filters == GitLogFilterCollection())
        }
    }

    @Test
    func typingDebouncesIntoTheTextFilterAndFlagsReapplyIt() async throws {
        try await withTempDir { dir in
            let manager = makeManager(dir)
            let viewModel = GitLogViewModel()
            let model = GitLogFilterBarModel(viewModel: viewModel, debounce: .milliseconds(5))
            let hosted = host(manager) { GitLogFilterBar(viewModel: viewModel, model: model) }
            defer { hosted.close() }
            try await hosted.settle(.milliseconds(60))

            model.text = "fix"
            try await eventually { viewModel.filters.text?.text == "fix" }
            #expect(viewModel.filters.text?.isRegex == false)
            try await hosted.settle(.milliseconds(60))

            model.usesRegex = true
            model.text = "fi.*x"
            try await eventually { viewModel.filters.text?.isRegex == true }

            model.matchesCase = true
            try await eventually { viewModel.filters.text?.matchesCase == true }
            try await hosted.settle(.milliseconds(60))

            model.clearText()
            try await eventually { viewModel.filters.text == nil }
            #expect(model.text.isEmpty)
        }
    }

    @Test
    func debounceStopsWhenCancelledAndSkipsUnchangedFilters() async {
        let viewModel = GitLogViewModel()
        let slow = GitLogFilterBarModel(viewModel: viewModel, debounce: .seconds(30))
        slow.text = "cancelled"
        let task = Task { await slow.applyDebouncedText() }
        task.cancel()
        await task.value
        #expect(viewModel.filters.text == nil)

        let quick = GitLogFilterBarModel(viewModel: viewModel, debounce: .zero)
        await quick.applyDebouncedText()
        #expect(viewModel.filters == GitLogFilterCollection())

        quick.text = "abc"
        await quick.applyDebouncedText()
        #expect(viewModel.filters.text?.text == "abc")
        #expect(quick.textState == GitLogFilterBarModel.TextState(text: "abc", matchesCase: false, usesRegex: false))
    }

    @Test
    func controlActionsFlipModelState() {
        let model = GitLogFilterBarModel(viewModel: GitLogViewModel())
        model.text = "x"
        model.clearText()
        #expect(model.text.isEmpty)

        model.toggleMatchCase()
        model.toggleRegex()
        #expect(model.matchesCase)
        #expect(model.usesRegex)
        model.toggleMatchCase()
        model.toggleRegex()
        #expect(model.matchesCase == false)
        #expect(model.usesRegex == false)

        model.toggler(\.showsBranches)()
        model.toggler(\.showsUsers)()
        model.toggler(\.showsDates)()
        model.toggler(\.showsPaths)()
        #expect(model.showsBranches && model.showsUsers && model.showsDates && model.showsPaths)
        model.toggler(\.showsBranches)()
        model.toggler(\.showsUsers)()
        model.toggler(\.showsDates)()
        model.toggler(\.showsPaths)()
        #expect(model.showsBranches == false)
        #expect(model.showsUsers == false)
        #expect(model.showsDates == false)
        #expect(model.showsPaths == false)
    }

    @Test
    func popoversPresentAndDismissThroughTheirModelFlags() async throws {
        try await withTempDir { dir in
            let manager = makeManager(dir)
            manager.branches = [localBranch("main"), remoteBranch("origin", "main")]
            let viewModel = GitLogViewModel()
            let model = GitLogFilterBarModel(viewModel: viewModel, debounce: .milliseconds(5))
            let hosted = host(manager, size: NSSize(width: 520, height: 420)) {
                GitLogFilterBar(viewModel: viewModel, model: model)
            }
            defer { hosted.close() }
            try await hosted.settle(.milliseconds(60))

            for flag in [\GitLogFilterBarModel.showsBranches, \.showsUsers, \.showsDates, \.showsPaths] {
                model.toggler(flag)()
                try await hosted.settle(.milliseconds(120))
                model[keyPath: flag] = false
                try await hosted.settle(.milliseconds(60))
            }
            #expect(hosted.renders())
        }
    }

    @Test
    func branchPopupListsBranchesAndChoosesFilters() async throws {
        try await withTempDir { dir in
            let manager = makeManager(dir)
            manager.branches = [
                localBranch("main"),
                localBranch("feature/x"),
                remoteBranch("origin", "main"),
                remoteBranch("origin", "dev")
            ]
            manager.currentBranch = localBranch("main")
            let viewModel = GitLogViewModel()
            let model = GitLogFilterBarModel(viewModel: viewModel)
            let hosted = host(manager, size: NSSize(width: 300, height: 320)) { GitLogBranchFilterPopup(model: model) }
            defer { hosted.close() }
            try await hosted.settle(.milliseconds(60))
            #expect(hosted.renders())
            let initial = hosted.snapshot()
            #expect(model.parentBinding(.noMerges).wrappedValue == false)

            model.showsBranches = true
            model.branchAction(.fromBranch("feature/x"))()
            try await eventually { viewModel.filters.branch == .fromBranch("feature/x") }
            #expect(model.showsBranches == false)
            try await hosted.settle(.milliseconds(60))
            #expect(HostedView.pixelsDiffer(initial, hosted.snapshot()))

            model.branchAction(.fromBranch("HEAD"))()
            try await eventually { viewModel.filters.branch == .fromBranch("HEAD") }
            try await hosted.settle(.milliseconds(60))

            model.branchAction(.fromBranch("origin/dev"))()
            try await eventually { viewModel.filters.branch == .fromBranch("origin/dev") }

            model.branchAction(nil)()
            try await eventually { viewModel.filters.branch == nil }
            try await hosted.settle(.milliseconds(60))
            #expect(hosted.renders())
        }
    }

    @Test
    func userPopupListsAuthorsAndTogglesSelection() async throws {
        try await withTempDir { dir in
            let fixture = try await GitMergeFixture(root: dir)
            try fixture.write("a.txt", "a\n")
            try await fixture.commit("first")
            try fixture.write("b.txt", "b\n")
            try await fixture.run("add", "-A")
            try await fixture.run("commit", "-q", "-m", "second", "--author=Alice Smith <alice@example.com>")
            let manager = makeManager(dir)
            let viewModel = GitLogViewModel()
            await viewModel.load(manager: manager)
            #expect(viewModel.availableUsers.count == 2)

            let model = GitLogFilterBarModel(viewModel: viewModel)
            let hosted = host(manager, size: NSSize(width: 320, height: 320)) { GitLogUserFilterPopup(model: model) }
            defer { hosted.close() }
            try await hosted.settle(.milliseconds(60))
            #expect(hosted.renders())
            let initial = hosted.snapshot()

            model.toggleUserAction(GitLogUserFilter.me)()
            try await eventually { viewModel.filters.user?.userNames == [GitLogUserFilter.me] }
            try await hosted.settle(.milliseconds(60))
            #expect(HostedView.pixelsDiffer(initial, hosted.snapshot()))

            model.toggleUserAction("Alice Smith")()
            try await eventually { viewModel.filters.user?.userNames == [GitLogUserFilter.me, "Alice Smith"] }
            try await hosted.settle(.milliseconds(60))

            model.toggleUserAction(GitLogUserFilter.me)()
            try await eventually {
                viewModel.filters.user?.userNames == ["Alice Smith"]
                    && viewModel.visibleCommits.map(\.subject) == ["second"]
            }
            try await hosted.settle(.milliseconds(60))

            model.toggleUserAction("Alice Smith")()
            try await eventually { viewModel.filters.user == nil && viewModel.visibleCommits.count == 2 }

            model.toggleUserAction("Alice Smith")()
            try await eventually { viewModel.filters.user?.userNames == ["Alice Smith"] }
            model.clearUsersAction()()
            try await eventually { viewModel.filters.user == nil && viewModel.visibleCommits.count == 2 }
            try await hosted.settle(.milliseconds(60))
            #expect(hosted.renders())
        }
    }

    @Test
    func dateSummaryCoversEveryBoundCombination() async {
        let viewModel = GitLogViewModel()
        let model = GitLogFilterBarModel(viewModel: viewModel)
        let afterText = after.formatted(date: .abbreviated, time: .omitted)
        let beforeText = before.formatted(date: .abbreviated, time: .omitted)
        #expect(model.dateSummary == nil)

        await viewModel.setFilters(GitLogFilterCollection(date: GitLogDateFilter(after: after, before: before)))
        #expect(model.dateSummary == "\(afterText) – \(beforeText)")

        await viewModel.setFilters(GitLogFilterCollection(date: GitLogDateFilter(after: after, before: nil)))
        #expect(model.dateSummary == "since \(afterText)")

        await viewModel.setFilters(GitLogFilterCollection(date: GitLogDateFilter(after: nil, before: before)))
        #expect(model.dateSummary == "until \(beforeText)")

        await viewModel.setFilters(GitLogFilterCollection(date: GitLogDateFilter(after: nil, before: nil)))
        #expect(model.dateSummary == nil)
    }

    @Test
    func popupLabelShowsTheValueOnlyWhenTheFilterIsActive() {
        #expect(GitLogFilterBar.popupLabel(title: "Branch", value: nil) == "Branch")
        #expect(GitLogFilterBar.popupLabel(title: "Branch", value: "") == "Branch")
        #expect(GitLogFilterBar.popupLabel(title: "Branch", value: "feature") == "Branch: feature")
    }

    @Test
    func datePopupAppliesPresetsRangesAndClear() async throws {
        let viewModel = GitLogViewModel()
        let model = GitLogFilterBarModel(viewModel: viewModel)
        let hosted = HostedViewFixture.host(size: NSSize(width: 280, height: 420)) { GitLogDateFilterPopup(model: model) }
        defer { hosted.close() }
        try await hosted.settle(.milliseconds(60))
        #expect(hosted.renders())
        let collapsed = hosted.snapshot()

        model.usesAfter = true
        model.usesBefore = true
        try await hosted.settle(.milliseconds(60))
        #expect(HostedView.pixelsDiffer(collapsed, hosted.snapshot()))

        for preset in GitLogDatePreset.allCases {
            model.showsDates = true
            model.presetAction(preset)()
            try await eventually { appliedPreset(preset, in: viewModel) }
            #expect(model.showsDates == false)
        }

        model.afterDate = after
        model.beforeDate = before
        model.applyDates()
        try await eventually { viewModel.filters.date == GitLogDateFilter(after: after, before: before) }

        model.usesBefore = false
        model.applyDates()
        try await eventually { viewModel.filters.date == GitLogDateFilter(after: after, before: nil) }

        model.usesAfter = false
        model.usesBefore = true
        model.applyDates()
        try await eventually { viewModel.filters.date == GitLogDateFilter(after: nil, before: before) }

        model.usesBefore = false
        model.applyDates()
        try await eventually { viewModel.filters.date == nil }

        model.usesAfter = true
        model.usesBefore = true
        model.applyDates()
        try await eventually { viewModel.filters.date != nil }
        model.showsDates = true
        model.clearDates()
        #expect(model.usesAfter == false)
        #expect(model.usesBefore == false)
        #expect(model.showsDates == false)
        try await eventually { viewModel.filters.date == nil }
        try await hosted.settle(.milliseconds(60))
        #expect(hosted.renders())
    }

    @Test
    func pathsPopupAppliesAndClearsRepositoryPaths() async throws {
        let viewModel = GitLogViewModel()
        let model = GitLogFilterBarModel(viewModel: viewModel)
        let hosted = HostedViewFixture.host(size: NSSize(width: 320, height: 240)) { GitLogPathsFilterPopup(model: model) }
        defer { hosted.close() }
        try await hosted.settle(.milliseconds(60))
        #expect(hosted.renders())

        model.pathsText = "src, docs\n  README.md \n"
        model.showsPaths = true
        model.applyPaths()
        #expect(model.showsPaths == false)
        try await eventually { viewModel.filters.structure?.paths == ["src", "docs", "README.md"] }
        try await hosted.settle(.milliseconds(60))

        model.showsPaths = true
        model.clearPaths()
        #expect(model.pathsText.isEmpty)
        #expect(model.showsPaths == false)
        try await eventually { viewModel.filters.structure == nil }
        try await hosted.settle(.milliseconds(60))
        #expect(hosted.renders())
    }

    @Test
    func optionsMenuTogglesParentAndFirstParentFilters() async throws {
        let viewModel = GitLogViewModel()
        let model = GitLogFilterBarModel(viewModel: viewModel)
        let hosted = HostedViewFixture.host(size: NSSize(width: 280, height: 160)) { GitLogFilterOptionItems(model: model) }
        defer { hosted.close() }
        try await hosted.settle(.milliseconds(60))
        #expect(hosted.renders())

        let noMerges = model.parentBinding(.noMerges)
        let onlyMerges = model.parentBinding(.onlyMerges)
        #expect(noMerges.wrappedValue == false)
        #expect(onlyMerges.wrappedValue == false)

        noMerges.wrappedValue = true
        try await eventually { viewModel.filters.parent == .noMerges }
        #expect(noMerges.wrappedValue)
        #expect(onlyMerges.wrappedValue == false)
        try await hosted.settle(.milliseconds(60))

        onlyMerges.wrappedValue = true
        try await eventually { viewModel.filters.parent == .onlyMerges }

        onlyMerges.wrappedValue = false
        try await eventually { viewModel.filters.parent == nil }

        let firstParent = model.firstParentBinding
        #expect(firstParent.wrappedValue == false)
        firstParent.wrappedValue = true
        try await eventually { viewModel.options.firstParent }
        #expect(firstParent.wrappedValue)
        try await hosted.settle(.milliseconds(60))

        firstParent.wrappedValue = false
        try await eventually { viewModel.options.firstParent == false }
    }
}
