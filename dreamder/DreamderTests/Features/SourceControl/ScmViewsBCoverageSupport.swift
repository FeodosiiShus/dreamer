import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
final class ScmViewsBCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

@MainActor
struct ScmViewsBRepository {
    let directory: URL
    let work: URL
    let remote: URL
    let fixture: GitMergeFixture
    let remoteFixture: GitMergeFixture
    let workspace: WorkspaceDocument
    let manager: SourceControlManager

    static func make(in directory: URL, pushed: Bool) async throws -> ScmViewsBRepository {
        let work = directory.appending(path: "work", directoryHint: .isDirectory)
        let remote = directory.appending(path: "remote.git", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: remote, withIntermediateDirectories: true)
        let remoteFixture = GitMergeFixture(existing: remote)
        try await remoteFixture.run("init", "--bare", "-q", "-b", "main")
        let fixture = try await GitMergeFixture(root: work)
        try fixture.write("a.txt", "a\n")
        try await fixture.commit("initial")
        try await fixture.run("remote", "add", "origin", remote.path(percentEncoded: false))
        if pushed {
            try await fixture.run("push", "-q", "-u", "origin", "main")
        }
        let workspace = try HostedViewFixture.makeWorkspace(in: work)
        let manager = try #require(workspace.sourceControlManager)
        await manager.branchOpsRefresh()
        return ScmViewsBRepository(
            directory: directory,
            work: work,
            remote: remote,
            fixture: fixture,
            remoteFixture: remoteFixture,
            workspace: workspace,
            manager: manager
        )
    }

    func host<Content: View>(_ content: () -> Content) throws -> HostedView {
        try HostedViewFixture.hostInWorkspace(workspace, content)
    }

    func selectOriginAndCurrentBranch() throws {
        let remote = try #require(manager.remotes.first)
        let branch = try #require(manager.currentBranch)
        manager.operationRemote = remote
        manager.operationBranch = branch
    }

    func headCommit() async throws -> String {
        try await fixture.run("rev-parse", "HEAD").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func remoteHead() async throws -> String {
        try await remoteFixture.run("rev-parse", "main").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func commitOnRemoteFromAnotherClone(file: String) async throws {
        let parent = GitMergeFixture(existing: directory)
        try await parent.run("clone", "-q", remote.path(percentEncoded: false), "other")
        let other = GitMergeFixture(existing: directory.appending(path: "other", directoryHint: .isDirectory))
        try await other.run("config", "user.email", "other@dreamder.test")
        try await other.run("config", "user.name", "Other")
        try await other.run("config", "commit.gpgsign", "false")
        try other.write(file, "from another clone\n")
        try await other.commit("another clone")
        try await other.run("push", "-q", "origin", "main")
    }

    func removeRemote() throws {
        try FileManager.default.removeItem(at: remote)
    }
}
