import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct GitLogBranchesPaneCoverageTests {
    private func makeBranchedRepository(_ dir: URL) async throws {
        let fixture = try await GitMergeFixture(root: dir)
        try fixture.write("a.txt", "a\n")
        try await fixture.commit("initial")
        try await fixture.run("checkout", "-q", "-b", "feature")
        try fixture.write("f.txt", "f\n")
        try await fixture.commit("Feature subject")
        try await fixture.run("checkout", "-q", "main")
        try await fixture.run("update-ref", "refs/remotes/origin/main", "main")
        try await fixture.run("update-ref", "refs/remotes/origin/feature", "feature")
        try await fixture.run("config", "remote.origin.url", dir.path(percentEncoded: false))
        try await fixture.run("config", "remote.origin.fetch", "+refs/heads/*:refs/remotes/origin/*")
        try await fixture.run("config", "branch.main.remote", "origin")
        try await fixture.run("config", "branch.main.merge", "refs/heads/main")
    }

    @Test
    func rendersHeadLocalAndRemoteGroupsAndTheRowActionsFilterTheLog() async throws {
        try await withTempDir { dir in
            try await makeBranchedRepository(dir)
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let manager = try #require(workspace.sourceControlManager)
            await manager.refreshBranches()
            await manager.refreshCurrentBranch()
            #expect(manager.orderedLocalBranches.map(\.name) == ["main", "feature"])
            #expect(manager.orderedLocalBranches.first?.upstream == "origin/main")
            #expect(manager.branches.filter(\.isRemote).map(\.name).sorted() == ["origin/feature", "origin/main"])

            let model = GitLogViewModel()
            await model.load(manager: manager)
            let pane = GitLogBranchesPane(viewModel: model)
            let hosted = try HostedViewFixture.hostInWorkspace(workspace) { pane }
            defer { hosted.close() }
            try await hosted.settle()
            #expect(hosted.renders())
            let headSelected = hosted.snapshot()

            pane.selectionAction(.fromBranch("feature"))()
            try await eventually { model.filters.branch == .fromBranch("feature") }
            try await hosted.settle()
            let featureSelected = hosted.snapshot()
            #expect(HostedView.pixelsDiffer(headSelected, featureSelected))
            #expect(model.tabTitle == "Log: feature")

            pane.selectionAction(.fromBranch("origin/main"))()
            try await eventually { model.filters.branch == .fromBranch("origin/main") }
            try await hosted.settle()
            #expect(HostedView.pixelsDiffer(featureSelected, hosted.snapshot()))

            pane.selectionAction(nil)()
            try await eventually { model.filters.branch == nil }
            try await hosted.settle()
            #expect(hosted.renders())
            #expect(model.tabTitle == "Log")
        }
    }

    @Test
    func rendersOnlyTheHeadRowWithoutBranches() async throws {
        try await withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let manager = try #require(workspace.sourceControlManager)
            #expect(manager.orderedLocalBranches.isEmpty)
            #expect(manager.branches.isEmpty)

            let hosted = try HostedViewFixture.hostInWorkspace(workspace) {
                GitLogBranchesPane(viewModel: GitLogViewModel())
            }
            defer { hosted.close() }
            try await hosted.settle()
            #expect(hosted.renders())
        }
    }

    @Test
    func rendersLocalBranchesWithoutRemotes() async throws {
        try await withTempDir { dir in
            let fixture = try await GitMergeFixture(root: dir)
            try fixture.write("a.txt", "a\n")
            try await fixture.commit("initial")
            try await fixture.run("branch", "topic")
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let manager = try #require(workspace.sourceControlManager)
            await manager.refreshBranches()
            await manager.refreshCurrentBranch()
            #expect(manager.orderedLocalBranches.map(\.name) == ["main", "topic"])

            let hosted = try HostedViewFixture.hostInWorkspace(workspace) {
                GitLogBranchesPane(viewModel: GitLogViewModel())
            }
            defer { hosted.close() }
            try await hosted.settle()
            #expect(hosted.renders())
        }
    }

    @Test
    func rowRendersEveryStateAndForwardsTapsAndHover() async throws {
        var taps = 0
        let plain = GitLogBranchRow(title: "main", subtitle: nil, icon: "vcs/branch", isSelected: false) { taps += 1 }
        let withSubtitle = GitLogBranchRow(
            title: "main",
            subtitle: "origin/main",
            icon: "vcs/branch",
            isSelected: false
        ) { taps += 1 }
        let selected = GitLogBranchRow(
            title: "main",
            subtitle: "origin/main",
            icon: "vcs/branch",
            isSelected: true
        ) { taps += 1 }

        let plainView = HostedViewFixture.host(size: NSSize(width: 240, height: 40)) { plain }
        let subtitleView = HostedViewFixture.host(size: NSSize(width: 240, height: 40)) { withSubtitle }
        let selectedView = HostedViewFixture.host(size: NSSize(width: 240, height: 40)) { selected }
        defer {
            plainView.close()
            subtitleView.close()
            selectedView.close()
        }
        try await plainView.settle()
        try await subtitleView.settle()
        try await selectedView.settle()
        #expect(plainView.renders())
        #expect(subtitleView.renders())
        #expect(HostedView.pixelsDiffer(plainView.snapshot(), subtitleView.snapshot()))
        #expect(HostedView.pixelsDiffer(subtitleView.snapshot(), selectedView.snapshot()))

        plain.action()
        withSubtitle.action()
        selected.action()
        #expect(taps == 3)

        plain.setHovering(true)
        plain.setHovering(false)
    }

    @Test
    func rowBackgroundPrefersSelectionThenHover() {
        #expect(GitLogBranchRow.background(isSelected: true, isHovering: true) == Islands.actionHover)
        #expect(GitLogBranchRow.background(isSelected: true, isHovering: false) == Islands.actionHover)
        #expect(GitLogBranchRow.background(isSelected: false, isHovering: true) == Islands.hover)
        #expect(GitLogBranchRow.background(isSelected: false, isHovering: false) == Color.clear)
    }

    @Test
    func remoteBranchFilterNameDropsTheRemotesPrefix() {
        let remote = GitBranch(
            name: "origin/main",
            longName: "refs/remotes/origin/main",
            upstream: nil,
            ahead: 0,
            behind: 0
        )
        let local = GitBranch(name: "main", longName: "refs/heads/main", upstream: nil, ahead: 0, behind: 0)
        let detached = GitBranch(name: "odd", longName: "refs/other/odd", upstream: nil, ahead: 0, behind: 0)

        #expect(remote.logFilterName == "origin/main")
        #expect(local.logFilterName == "main")
        #expect(detached.logFilterName == "odd")
    }
}
