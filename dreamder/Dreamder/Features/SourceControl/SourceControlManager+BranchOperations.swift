import Foundation

extension SourceControlManager {
    func branchOpsRefresh() async {
        try? await refreshRemotes()
        await refreshBranches()
        await refreshCurrentBranch()
        await refreshAllChangedFiles()
        await refreshNumberOfUnsyncedCommits()
    }

    func branchOpsTags() async -> [GitTag] {
        (try? await gitClient.branchOpsListTags()) ?? []
    }

    func branchOpsRecentBranchNames(limit: Int) async -> [String] {
        (try? await gitClient.branchOpsRecentBranchNames(limit: limit)) ?? []
    }

    func branchOpsOperationState() async -> GitBranchOperationState {
        await gitClient.branchOpsOperationState()
    }

    func branchOpsCheckoutLocal(_ name: String) async throws {
        try await gitClient.branchOpsCheckoutLocal(name)
        await branchOpsRefresh()
    }

    func branchOpsCheckoutRemote(_ shortName: String) async throws {
        try await gitClient.branchOpsCheckoutRemote(shortName)
        await branchOpsRefresh()
    }

    func branchOpsCheckoutRemoteTrackingBranch(
        localName: String,
        remote: String,
        overwrite: Bool = false
    ) async throws {
        try await gitClient.branchOpsCheckoutRemoteTrackingBranch(
            localName: localName,
            remote: remote,
            overwrite: overwrite
        )
        await branchOpsRefresh()
    }

    func branchOpsResetLocalBranchToRemote(localName: String, remote: String) async throws {
        try await gitClient.branchOpsResetLocalBranchToRemote(localName: localName, remote: remote)
        await branchOpsRefresh()
    }

    func branchOpsCheckoutRevision(_ revision: String) async throws {
        try await gitClient.branchOpsCheckoutRevision(revision)
        await branchOpsRefresh()
    }

    func branchOpsBranchExists(_ name: String) async -> Bool {
        (try? await gitClient.branchOpsBranchExists(name)) ?? false
    }

    func branchOpsRevision(_ revision: String) async throws -> String {
        try await gitClient.branchOpsRevision(revision)
    }

    func branchOpsCommitCount(branch: String, notIn base: String) async throws -> Int {
        try await gitClient.branchOpsCommitCount(branch: branch, notIn: base)
    }

    func branchOpsCommits(branch: String, notIn base: String) async throws -> [BranchesCompareCommit] {
        try await gitClient.branchOpsCommits(branch: branch, notIn: base)
    }

    func branchOpsCreateBranch(
        name: String,
        from ref: String?,
        checkout: Bool = true,
        overwrite: Bool = false
    ) async throws {
        try await gitClient.branchOpsCreateBranch(
            name: name,
            from: ref,
            checkout: checkout,
            overwrite: overwrite
        )
        await branchOpsRefresh()
    }

    func branchOpsRenameBranch(oldName: String, newName: String, unsetUpstream: Bool = false) async throws {
        try await gitClient.branchOpsRenameBranch(
            oldName: oldName,
            newName: newName,
            unsetUpstream: unsetUpstream
        )
        await branchOpsRefresh()
    }

    func branchOpsDeleteLocalBranch(_ name: String, force: Bool = false) async throws {
        try await gitClient.branchOpsDeleteLocalBranch(name, force: force)
        await branchOpsRefresh()
    }

    func branchOpsUnmergedCommits(branch: String, base: String) async throws -> [String] {
        try await gitClient.branchOpsUnmergedCommits(branch: branch, base: base)
    }

    func branchOpsRestoreBranch(name: String, at revision: String) async throws {
        try await gitClient.branchOpsRestoreBranch(name: name, at: revision)
        await branchOpsRefresh()
    }

    func branchOpsRestoreTag(name: String, at revision: String) async throws {
        try await gitClient.branchOpsRestoreTag(name: name, at: revision)
        await branchOpsRefresh()
    }

    func branchOpsDeleteRemoteBranch(remote: String, branch: String) async throws {
        try await gitClient.branchOpsDeleteRemoteBranch(remote: remote, branch: branch)
        await branchOpsRefresh()
    }

    func branchOpsDeleteTag(_ name: String) async throws {
        try await gitClient.branchOpsDeleteTag(name)
        await branchOpsRefresh()
    }

    @discardableResult
    func branchOpsMerge(_ ref: String) async throws -> Bool {
        let conflicted = try await gitClient.branchOpsMerge(ref)
        await branchOpsRefresh()
        return conflicted
    }

    @discardableResult
    func branchOpsRebase(onto ref: String) async throws -> Bool {
        let conflicted = try await gitClient.branchOpsRebase(onto: ref)
        await branchOpsRefresh()
        return conflicted
    }

    @discardableResult
    func branchOpsCheckoutAndRebase(_ branch: String, onto ref: String) async throws -> Bool {
        let conflicted = try await gitClient.branchOpsCheckoutAndRebase(branch, onto: ref)
        await branchOpsRefresh()
        return conflicted
    }

    func branchOpsRebaseAbort() async throws {
        try await gitClient.branchOpsRebaseAbort()
        await branchOpsRefresh()
    }

    func branchOpsRebaseContinue() async throws {
        try await gitClient.branchOpsRebaseContinue()
        await branchOpsRefresh()
    }

    func branchOpsRebaseSkip() async throws {
        try await gitClient.branchOpsRebaseSkip()
        await branchOpsRefresh()
    }

    func branchOpsMergeAbort() async throws {
        try await gitClient.branchOpsMergeAbort()
        await branchOpsRefresh()
    }

    func branchOpsCherryPickAbort() async throws {
        try await gitClient.branchOpsCherryPickAbort()
        await branchOpsRefresh()
    }

    func branchOpsCherryPickContinue() async throws {
        try await gitClient.branchOpsCherryPickContinue()
        await branchOpsRefresh()
    }

    func branchOpsFetchAll() async throws {
        try await gitClient.branchOpsFetchAll()
        await refreshNumberOfUnsyncedCommits()
    }

    func branchOpsUpdateProject() async throws {
        try await gitClient.branchOpsPullCurrent()
        await branchOpsRefresh()
    }

    func branchOpsPull(ref: String, rebase: Bool) async throws {
        try await gitClient.branchOpsPull(ref: ref, rebase: rebase)
        await branchOpsRefresh()
    }

    func branchOpsSetUpstream(branch: String, upstream: String?) async throws {
        try await gitClient.branchOpsSetUpstream(branch: branch, upstream: upstream)
        await branchOpsRefresh()
    }

    func branchOpsUpdateBranch(name: String, upstream: String, isCurrent: Bool) async throws {
        try await gitClient.branchOpsUpdateBranch(name: name, upstream: upstream, isCurrent: isCurrent)
        await branchOpsRefresh()
    }

    func branchOpsAddWorktree(path: String, ref: String?) async throws {
        try await gitClient.branchOpsAddWorktree(path: path, ref: ref)
        await branchOpsRefresh()
    }

    func branchOpsPushTag(name: String, remote: String) async throws {
        try await gitClient.branchOpsPushTag(name: name, remote: remote)
        await branchOpsRefresh()
    }
}
