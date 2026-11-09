import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct GitLogCommitTableCoverageTests {
    private func makeHistory(_ dir: URL) async throws {
        let fixture = try await GitMergeFixture(root: dir)
        try fixture.write("a.txt", "a\n")
        try await fixture.commit("initial")
        try await fixture.run("checkout", "-q", "-b", "feature")
        try fixture.write("f.txt", "f\n")
        try await fixture.commit("Feature subject")
        try await fixture.run("checkout", "-q", "main")
        try fixture.write("a.txt", "main\n")
        try await fixture.commit("Main change")
        try await fixture.run("merge", "--no-ff", "-q", "-m", "Merge feature", "feature")
        try await fixture.run("tag", "v1")
        try await fixture.run("update-ref", "refs/remotes/origin/main", "main")
    }

    private func makeCommit(
        _ hash: String,
        subject: String,
        parents: [String] = [],
        refs: [GitLogRef] = []
    ) -> GitLogCommit {
        GitLogCommit(
            hash: hash,
            parents: parents,
            authorName: "Ann",
            authorEmail: "ann@example.com",
            date: Date(timeIntervalSinceNow: -7_200),
            refs: refs,
            subject: subject
        )
    }

    @Test
    func populatedTableRendersGraphRowsSelectionAndForwardsRowTaps() async throws {
        try await withTempDir { dir in
            try await makeHistory(dir)
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let manager = try #require(workspace.sourceControlManager)
            let model = GitLogViewModel()
            await model.load(manager: manager)

            let kinds = Set(model.commits.flatMap(\.refs).map(\.kind))
            #expect(kinds == [.head, .branch, .remote, .tag])
            #expect(model.commits.contains { $0.isMerge })
            #expect(model.graphRows.count == model.commits.count)

            let table = GitLogCommitTable(viewModel: model)
            let hosted = HostedViewFixture.host { table }
            defer { hosted.close() }
            try await hosted.settle()
            #expect(hosted.renders())
            let firstSelected = hosted.snapshot()

            let feature = try #require(model.commits.first { $0.subject == "Feature subject" })
            table.selectionAction(hash: feature.hash)()
            try await eventually { model.selectedHash == feature.hash }
            try await eventually { model.selectedMessage == "Feature subject" && model.selectedFiles.count == 1 }
            try await hosted.settle()
            #expect(HostedView.pixelsDiffer(firstSelected, hosted.snapshot()))
        }
    }

    @Test
    func tableShowsTheLoadingPlaceholderWhileTheLogIsFetched() async throws {
        try await withTempDir { dir in
            try await makeHistory(dir)
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let manager = try #require(workspace.sourceControlManager)
            let model = GitLogViewModel()
            let loading = Task { await model.load(manager: manager) }
            var attempts = 0
            while !model.isLoading, attempts < 10_000 {
                attempts += 1
                await Task.yield()
            }
            #expect(model.isLoading)

            let table = GitLogCommitTable(viewModel: model)
            #expect(table.placeholder == "Loading commits…")
            let hosted = HostedViewFixture.host { table }
            defer { hosted.close() }
            hosted.layout()

            await loading.value
            try await hosted.settle()
            #expect(hosted.renders())
            #expect(model.commits.isEmpty == false)
        }
    }

    @Test
    func tableShowsTheErrorOfAFailedLoad() async throws {
        try await withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let manager = try #require(workspace.sourceControlManager)
            let model = GitLogViewModel()
            await model.load(manager: manager)
            let message = try #require(model.errorMessage)

            let table = GitLogCommitTable(viewModel: model)
            #expect(table.placeholder == message)
            let hosted = HostedViewFixture.host { table }
            defer { hosted.close() }
            try await hosted.settle()
            #expect(hosted.renders())
        }
    }

    @Test
    func tableShowsNoCommitsBeforeAnyLoad() async throws {
        let model = GitLogViewModel()
        let table = GitLogCommitTable(viewModel: model)
        #expect(table.placeholder == "No commits")

        let hosted = HostedViewFixture.host { table }
        defer { hosted.close() }
        try await hosted.settle()
        #expect(hosted.renders())
    }

    @Test
    func tableShowsNoMatchingCommitsWhenTheSearchExcludesEverything() async throws {
        try await withTempDir { dir in
            try await makeHistory(dir)
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let manager = try #require(workspace.sourceControlManager)
            let model = GitLogViewModel()
            await model.load(manager: manager)

            let table = GitLogCommitTable(viewModel: model)
            let hosted = HostedViewFixture.host { table }
            defer { hosted.close() }
            try await hosted.settle()
            let populated = hosted.snapshot()

            await model.setFilters(model.filters.settingText("nothing-matches", isRegexpAllowed: false, isMatchCase: false))
            #expect(model.visibleCommits.isEmpty)
            #expect(model.commits.isEmpty == false)
            try await hosted.settle()
            #expect(hosted.renders())
            #expect(HostedView.pixelsDiffer(populated, hosted.snapshot()))

            await model.setFilters(model.filters.settingText("Feature subject", isRegexpAllowed: false, isMatchCase: false))
            #expect(model.visibleCommits.map(\.subject) == ["Feature subject"])
            try await hosted.settle()
            #expect(hosted.renders())
        }
    }

    @Test
    func rowRendersGraphlessMergeSelectedAndPlainStates() async throws {
        let plain = makeCommit("1111111111", subject: "Plain commit")
        let merge = makeCommit("2222222222", subject: "Merge commit", parents: ["1111111111", "3333333333"])
        let child = makeCommit("cccccccccc", subject: "Child", parents: ["1111111111"])
        let graphRow = try #require(GitLogGraphLayout.rows(for: [child, plain]).first)
        var taps = 0

        let rows = [
            GitLogCommitRow(commit: plain, graphRow: nil, laneCount: 2, isSelected: false) { taps += 1 },
            GitLogCommitRow(commit: plain, graphRow: graphRow, laneCount: 2, isSelected: false) { taps += 1 },
            GitLogCommitRow(commit: merge, graphRow: nil, laneCount: 1, isSelected: false) { taps += 1 },
            GitLogCommitRow(commit: plain, graphRow: nil, laneCount: 2, isSelected: true) { taps += 1 }
        ]
        var snapshots: [NSBitmapImageRep?] = []
        for row in rows {
            let hosted = HostedViewFixture.host(size: NSSize(width: 900, height: 40)) { row }
            defer { hosted.close() }
            try await hosted.settle()
            #expect(hosted.renders())
            snapshots.append(hosted.snapshot())
        }
        let base = try #require(snapshots.first)
        for other in snapshots.dropFirst() {
            #expect(HostedView.pixelsDiffer(base, other))
        }

        for row in rows {
            row.action()
            row.setHovering(true)
            row.setHovering(false)
        }
        #expect(taps == rows.count)
    }

    @Test
    func rowBackgroundPrefersSelectionThenHover() {
        #expect(GitLogCommitRow.background(isSelected: true, isHovering: true) == Islands.selection)
        #expect(GitLogCommitRow.background(isSelected: true, isHovering: false) == Islands.selection)
        #expect(GitLogCommitRow.background(isSelected: false, isHovering: true) == Islands.hover)
        #expect(GitLogCommitRow.background(isSelected: false, isHovering: false) == Color.clear)
    }

    @Test
    func refChipRendersEveryRefKind() async throws {
        let refs = [
            GitLogRef(name: "HEAD", kind: .head),
            GitLogRef(name: "main", kind: .branch),
            GitLogRef(name: "origin/main", kind: .remote),
            GitLogRef(name: "v1", kind: .tag)
        ]
        var snapshots: [NSBitmapImageRep?] = []
        for ref in refs {
            let hosted = HostedViewFixture.host(size: NSSize(width: 160, height: 40)) { GitLogRefChip(ref: ref) }
            defer { hosted.close() }
            try await hosted.settle()
            #expect(hosted.renders())
            snapshots.append(hosted.snapshot())
        }
        #expect(HostedView.pixelsDiffer(snapshots[1], snapshots[2]))
        #expect(HostedView.pixelsDiffer(snapshots[2], snapshots[3]))
        #expect(HostedView.pixelsDiffer(snapshots[1], snapshots[3]))
    }
}
