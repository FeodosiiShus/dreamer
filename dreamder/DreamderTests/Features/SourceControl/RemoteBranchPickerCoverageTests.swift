import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
struct ScmViewsAHarness {
    let root: URL
    let workspace: WorkspaceDocument
    let manager: SourceControlManager
    let repo: GitMergeFixture
    let remoteURL: URL

    var remotePath: String {
        remoteURL.path(percentEncoded: false)
    }

    static func make(
        in root: URL,
        withRemote: Bool = true,
        pushedBranches: [String] = ["main", "feature"]
    ) async throws -> ScmViewsAHarness {
        let workURL = root.appending(path: "work", directoryHint: .isDirectory)
        let remoteURL = root.appending(path: "remote.git", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: workURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: remoteURL, withIntermediateDirectories: true)
        let repo = try await GitMergeFixture(root: workURL)
        try repo.write("a.txt", "a\n")
        try await repo.commit("initial")
        try await GitMergeFixture(existing: remoteURL).run("init", "-q", "--bare", "-b", "main")
        if withRemote {
            try await repo.run("remote", "add", "origin", remoteURL.path(percentEncoded: false))
            for branch in pushedBranches {
                if branch == "main" {
                    try await repo.run("push", "-q", "-u", "origin", "main")
                } else {
                    try await repo.run("branch", branch)
                    try await repo.run("push", "-q", "origin", branch)
                }
            }
        }
        let workspace = try HostedViewFixture.makeWorkspace(in: workURL)
        let manager = try #require(workspace.sourceControlManager)
        let harness = ScmViewsAHarness(
            root: root,
            workspace: workspace,
            manager: manager,
            repo: repo,
            remoteURL: remoteURL
        )
        try await harness.refresh()
        return harness
    }

    func refresh() async throws {
        await manager.refreshCurrentBranch()
        await manager.refreshBranches()
        try await manager.refreshRemotes()
    }

    func publishFromAnotherClone(branches: [String]) async throws {
        let cloneURL = root.appending(path: "other", directoryHint: .isDirectory)
        try await GitMergeFixture(existing: root).run("clone", "-q", remotePath, "other")
        let other = GitMergeFixture(existing: cloneURL)
        try await other.run("config", "user.email", "other@dreamder.test")
        try await other.run("config", "user.name", "Other")
        try await other.run("config", "commit.gpgsign", "false")
        try other.write("other.txt", "other\n")
        try await other.commit("from another clone")
        for branch in branches {
            try await other.run("push", "-q", "origin", "HEAD:refs/heads/\(branch)")
        }
    }

    func close() {
        workspace.close()
    }
}

@MainActor
enum ScmViewsAControls {
    static func fieldValues(in hosted: HostedView) -> [String] {
        hosted.views(of: NSTextField.self).map(\.stringValue)
    }
}

@MainActor
@Observable
final class ScmViewsAPickerProbe {
    var branch: GitBranch?
    var remote: GitRemote?
}

@MainActor
struct ScmViewsAPickerHost: View {
    let probe: ScmViewsAPickerProbe
    let canCreateBranch: Bool

    var body: some View {
        @Bindable var probe = probe
        Form {
            Section {
                RemoteBranchPicker(
                    branch: $probe.branch,
                    remote: $probe.remote,
                    onSubmit: {},
                    canCreateBranch: canCreateBranch
                )
            }
        }
        .formStyle(.grouped)
    }
}

@MainActor
@Suite(.uiGate)
struct RemoteBranchPickerCoverage {
    private func host(
        _ harness: ScmViewsAHarness,
        probe: ScmViewsAPickerProbe,
        canCreateBranch: Bool
    ) throws -> HostedView {
        try HostedViewFixture.hostInWorkspace(harness.workspace) {
            ScmViewsAPickerHost(probe: probe, canCreateBranch: canCreateBranch)
        }
    }

    @Test
    func selectsTheUpstreamRemoteAndBranchOfTheCurrentBranch() async throws {
        try await withTempDir { dir in
            let harness = try await ScmViewsAHarness.make(in: dir)
            defer { harness.close() }
            #expect(harness.manager.currentBranch?.upstream == "origin/main")
            let probe = ScmViewsAPickerProbe()
            let hosted = try host(harness, probe: probe, canCreateBranch: false)
            defer { hosted.close() }

            try await eventually { probe.branch?.name == "main" }
            #expect(probe.remote?.name == "origin")
        }
    }

    @Test
    func offersToCreateTheCurrentBranchWhenTheRemoteLacksIt() async throws {
        try await withTempDir { dir in
            let harness = try await ScmViewsAHarness.make(in: dir)
            defer { harness.close() }
            try await harness.repo.run("checkout", "-q", "-b", "topic")
            try await harness.refresh()
            let probe = ScmViewsAPickerProbe()
            let hosted = try host(harness, probe: probe, canCreateBranch: true)
            defer { hosted.close() }

            try await eventually { probe.branch?.name == "topic" }
            #expect(probe.remote?.name == "origin")
            #expect(probe.branch == harness.manager.currentBranch)
        }
    }

    @Test
    func fallsBackToTheFirstRemoteBranchWhenNothingIsTracked() async throws {
        try await withTempDir { dir in
            let harness = try await ScmViewsAHarness.make(in: dir)
            defer { harness.close() }
            try await harness.repo.run("checkout", "-q", "-b", "topic")
            try await harness.refresh()
            let probe = ScmViewsAPickerProbe()
            let hosted = try host(harness, probe: probe, canCreateBranch: false)
            defer { hosted.close() }

            try await eventually { probe.branch != nil }
            let first = try #require(probe.remote?.branches.first)
            #expect(probe.branch == first)
            #expect(probe.branch?.name == "feature")
        }
    }

    @Test
    func leavesTheRemoteEmptyWhenTheUpstreamRemoteIsUnknown() async throws {
        try await withTempDir { dir in
            let harness = try await ScmViewsAHarness.make(in: dir)
            defer { harness.close() }
            harness.manager.currentBranch = GitBranch(
                name: "topic",
                longName: "refs/heads/topic",
                upstream: "ghost/topic",
                ahead: 0,
                behind: 0
            )
            let probe = ScmViewsAPickerProbe()
            let hosted = try host(harness, probe: probe, canCreateBranch: false)
            defer { hosted.close() }

            try await hosted.settle()
            #expect(probe.remote == nil)
            #expect(probe.branch == nil)
            #expect(harness.manager.addExistingRemoteSheetIsPresented == false)
        }
    }

    @Test
    func withoutACurrentBranchTheFirstRemoteIsUsedAndNothingIsCreated() async throws {
        try await withTempDir { dir in
            let harness = try await ScmViewsAHarness.make(in: dir)
            defer { harness.close() }
            harness.manager.currentBranch = nil
            let probe = ScmViewsAPickerProbe()
            let creating = try host(harness, probe: probe, canCreateBranch: true)
            defer { creating.close() }

            try await eventually { probe.remote?.name == "origin" }
            try await creating.settle()
            #expect(probe.branch == nil)

            let secondProbe = ScmViewsAPickerProbe()
            let plain = try host(harness, probe: secondProbe, canCreateBranch: false)
            defer { plain.close() }

            try await eventually { secondProbe.branch != nil }
            #expect(secondProbe.branch == secondProbe.remote?.branches.first)
        }
    }

    @Test
    func aRemoteWithoutBranchesOffersTheCurrentBranchOnlyWhenCreatingIsAllowed() async throws {
        try await withTempDir { dir in
            let harness = try await ScmViewsAHarness.make(in: dir, pushedBranches: [])
            defer { harness.close() }
            let remote = try #require(harness.manager.remotes.first)
            #expect(remote.branches.isEmpty)

            let creatingProbe = ScmViewsAPickerProbe()
            let creating = try host(harness, probe: creatingProbe, canCreateBranch: true)
            defer { creating.close() }
            try await eventually { creatingProbe.branch?.name == "main" }

            let plainProbe = ScmViewsAPickerProbe()
            let plain = try host(harness, probe: plainProbe, canCreateBranch: false)
            defer { plain.close() }
            try await eventually { plainProbe.remote?.name == "origin" }
            try await plain.settle()
            #expect(plainProbe.branch == nil)
        }
    }

    @Test
    func changingTheRemoteReselectsABranchAndChoosingNoneOpensTheAddRemoteSheet() async throws {
        try await withTempDir { dir in
            let harness = try await ScmViewsAHarness.make(in: dir)
            defer { harness.close() }
            try await harness.manager.addRemote(name: "backup", location: harness.remotePath)
            let origin = try #require(harness.manager.remotes.first { $0.name == "origin" })
            let backup = try #require(harness.manager.remotes.first { $0.name == "backup" })
            #expect(backup.branches.isEmpty)
            let probe = ScmViewsAPickerProbe()
            probe.remote = origin
            probe.branch = origin.branches.first
            let hosted = try host(harness, probe: probe, canCreateBranch: false)
            defer { hosted.close() }
            try await hosted.settle()
            #expect(probe.remote == origin)
            #expect(probe.branch == origin.branches.first)

            probe.remote = backup
            try await eventually { probe.branch == nil }
            #expect(harness.manager.addExistingRemoteSheetIsPresented == false)

            probe.remote = nil
            try await eventually { harness.manager.addExistingRemoteSheetIsPresented }
        }
    }
}
