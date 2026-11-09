import Foundation

nonisolated struct GitBranchOperationState: Hashable {
    var isMerging = false
    var isRebasing = false
    var isCherryPicking = false
    var isReverting = false

    static let none = GitBranchOperationState()

    var hasOngoingOperation: Bool {
        isMerging || isRebasing || isCherryPicking || isReverting
    }
}

nonisolated extension GitClient {
    func branchOpsListTags() async throws -> [GitTag] {
        let output = try await run(arguments: [
            "for-each-ref", "--format=%(refname:short)|%(objectname:short)", "refs/tags"
        ])
        return GitTag.list(from: output)
    }

    func branchOpsRecentBranchNames(limit: Int) async throws -> [String] {
        let reflog = try await run(arguments: [
            "reflog", "--format=%gs",
            "--max-count", "\(BranchesPopupReflogParser.reflogEntryCount)",
            "--grep-reflog", "checkout:",
            "--"
        ])
        let localRefs = try await run(arguments: ["for-each-ref", "--format=%(refname)", "refs/heads"])
        return BranchesPopupReflogParser.recentBranchNames(
            from: reflog,
            existingBranches: BranchesPopupReflogParser.localBranchNames(fromRefs: localRefs),
            limit: limit
        )
    }

    func branchOpsOperationState() async -> GitBranchOperationState {
        guard let gitDirectory = try? await run(arguments: ["rev-parse", "--git-dir"])
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !gitDirectory.isEmpty else {
            return .none
        }
        let directory = gitDirectory.hasPrefix("/")
            ? URL(fileURLWithPath: gitDirectory)
            : directoryURL.appending(path: gitDirectory)
        let manager = FileManager.default
        var state = GitBranchOperationState()
        state.isMerging = manager.fileExists(atPath: directory.appending(path: "MERGE_HEAD").path(percentEncoded: false))
        state.isRebasing = manager.fileExists(atPath: directory.appending(path: "rebase-merge").path(percentEncoded: false))
            || manager.fileExists(atPath: directory.appending(path: "rebase-apply").path(percentEncoded: false))
        state.isCherryPicking = manager.fileExists(
            atPath: directory.appending(path: "CHERRY_PICK_HEAD").path(percentEncoded: false)
        )
        state.isReverting = manager.fileExists(atPath: directory.appending(path: "REVERT_HEAD").path(percentEncoded: false))
        return state
    }

    static func requireRefNames(_ names: String?...) throws {
        if let name = names.compactMap({ $0 }).first(where: { $0.hasPrefix("-") }) {
            throw GitClientError.outputError("Invalid reference name '\(name)': it must not start with '-'")
        }
    }

    func branchOpsRevision(_ revision: String) async throws -> String {
        try Self.requireRefNames(revision)
        return try await run(arguments: ["rev-parse", "--verify", "--end-of-options", revision])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func branchOpsBranchExists(_ name: String) async throws -> Bool {
        let result = try await runResult(arguments: ["rev-parse", "-q", "--verify", "refs/heads/\(name)"])
        guard result.success(ignoring: [1]) else {
            throw Self.error(for: result)
        }
        return !result.outputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func branchOpsCheckoutLocal(_ name: String) async throws {
        try Self.requireRefNames(name)
        try await branchOpsCheckedRun(["checkout", "--end-of-options", name])
    }

    func branchOpsCheckoutRemote(_ shortName: String) async throws {
        let parts = shortName.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2, !parts[1].isEmpty else {
            throw GitClientError.outputError("Invalid remote branch '\(shortName)'")
        }
        let localName = parts[1]
        try Self.requireRefNames(shortName, localName)
        if try await branchOpsBranchExists(localName) {
            try await branchOpsCheckoutLocal(localName)
        } else {
            try await branchOpsCheckoutRemoteTrackingBranch(localName: localName, remote: shortName)
        }
    }

    func branchOpsCheckoutRemoteTrackingBranch(
        localName: String,
        remote: String,
        overwrite: Bool = false
    ) async throws {
        try Self.requireRefNames(localName, remote)
        let flags = overwrite ? ["-B"] : ["--track", "-b"]
        try await branchOpsCheckedRun(["checkout"] + flags + [localName, "--end-of-options", remote])
    }

    func branchOpsResetLocalBranchToRemote(localName: String, remote: String) async throws {
        try Self.requireRefNames(localName, remote)
        try await branchOpsCheckedRun(["checkout", "-B", localName, "--end-of-options", remote])
    }

    func branchOpsCommitCount(branch: String, notIn base: String) async throws -> Int {
        try Self.requireRefNames(branch, base)
        let output = try await branchOpsCheckedRun(["rev-list", "--count", "--end-of-options", "\(base)..\(branch)"])
        return Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    func branchOpsCommits(branch: String, notIn base: String) async throws -> [BranchesCompareCommit] {
        try Self.requireRefNames(branch, base)
        let output = try await run(arguments: [
            "log", "--format=%h|%s|%an|%ad", "--date=short", "--end-of-options", "\(base)..\(branch)"
        ])
        return BranchesCompareCommit.list(from: output)
    }

    func branchOpsCheckoutRevision(_ revision: String) async throws {
        try Self.requireRefNames(revision)
        try await branchOpsCheckedRun(["checkout", "--end-of-options", revision])
    }

    func branchOpsCreateBranch(
        name: String,
        from ref: String?,
        checkout: Bool = true,
        overwrite: Bool = false
    ) async throws {
        switch (checkout, overwrite) {
        case (true, true):
            try await branchOpsCreateCheckedOutBranch(name: name, from: ref, flag: "-B")
        case (true, false):
            try await branchOpsCreateCheckedOutBranch(name: name, from: ref, flag: "-b")
        case (false, true):
            try await branchOpsCreateUncheckedBranch(name: name, from: ref, flag: "-f")
        case (false, false):
            try await branchOpsCreateUncheckedBranch(name: name, from: ref, flag: nil)
        }
    }

    func branchOpsRenameBranch(
        oldName: String,
        newName: String,
        unsetUpstream: Bool = false
    ) async throws {
        try Self.requireRefNames(oldName, newName)
        try await branchOpsCheckedRun(["branch", "-m", "--end-of-options", oldName, newName])
        if unsetUpstream {
            try await branchOpsCheckedRun(["branch", "--unset-upstream", "--end-of-options", newName])
        }
    }

    func branchOpsDeleteLocalBranch(_ name: String, force: Bool = false) async throws {
        try Self.requireRefNames(name)
        let result = try await runResult(arguments: ["branch", force ? "-D" : "-d", "--end-of-options", name])
        guard result.success else {
            let text = result.combinedText
            if !force, text.contains("not fully merged") || text.contains("not merged") {
                throw GitClientError.branchNotFullyMerged
            }
            throw Self.error(for: result)
        }
    }

    func branchOpsUnmergedCommits(branch: String, base: String) async throws -> [String] {
        try Self.requireRefNames(branch, base)
        let output = try await run(arguments: ["log", "--format=%h  %s", "--end-of-options", "\(base)..\(branch)"])
        return output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    func branchOpsRestoreBranch(name: String, at revision: String) async throws {
        try Self.requireRefNames(name, revision)
        try await branchOpsCheckedRun(["branch", "--end-of-options", name, revision])
    }

    func branchOpsRestoreTag(name: String, at revision: String) async throws {
        try Self.requireRefNames(name, revision)
        try await branchOpsCheckedRun(["tag", "--end-of-options", name, revision])
    }

    func branchOpsDeleteRemoteBranch(remote: String, branch: String) async throws {
        try Self.requireRefNames(remote, branch)
        try await branchOpsCheckedRun(["push", "--delete", "--end-of-options", remote, branch])
    }

    func branchOpsDeleteTag(_ name: String) async throws {
        try Self.requireRefNames(name)
        try await branchOpsCheckedRun(["tag", "-d", "--end-of-options", name])
    }

    func branchOpsMerge(_ ref: String) async throws -> Bool {
        try Self.requireRefNames(ref)
        let result = try await runResult(arguments: [
            "-c", "core.editor=true", "merge", "--no-edit", "--end-of-options", ref
        ])
        let state = await branchOpsOperationState()
        if state.isMerging || result.combinedText.contains("CONFLICT") {
            return true
        }
        guard result.success else {
            throw Self.error(for: result)
        }
        return false
    }

    func branchOpsRebase(onto ref: String) async throws -> Bool {
        try Self.requireRefNames(ref)
        let result = try await runResult(arguments: ["rebase", "--end-of-options", ref])
        let state = await branchOpsOperationState()
        let text = result.combinedText
        if state.isRebasing || text.contains("CONFLICT") || text.contains("could not apply") {
            return true
        }
        guard result.success else {
            throw Self.error(for: result)
        }
        return false
    }

    func branchOpsCheckoutAndRebase(_ branch: String, onto ref: String) async throws -> Bool {
        try Self.requireRefNames(branch, ref)
        try await branchOpsCheckoutLocal(branch)
        return try await branchOpsRebase(onto: ref)
    }

    func branchOpsRebaseAbort() async throws {
        try await branchOpsCheckedRun(["rebase", "--abort"])
    }

    func branchOpsRebaseContinue() async throws {
        try await branchOpsCheckedRun(["-c", "core.editor=true", "rebase", "--continue"])
    }

    func branchOpsRebaseSkip() async throws {
        try await branchOpsCheckedRun(["-c", "core.editor=true", "rebase", "--skip"])
    }

    func branchOpsMergeAbort() async throws {
        try await branchOpsCheckedRun(["merge", "--abort"])
    }

    func branchOpsCherryPickAbort() async throws {
        try await branchOpsCheckedRun(["cherry-pick", "--abort"])
    }

    func branchOpsCherryPickContinue() async throws {
        try await branchOpsCheckedRun(["-c", "core.editor=true", "cherry-pick", "--continue"])
    }

    func branchOpsFetchAll() async throws {
        try await branchOpsCheckedRun(["fetch", "--all", "--prune"])
    }

    func branchOpsPullCurrent() async throws {
        try await branchOpsCheckedRun(["pull", "--no-rebase"])
    }

    func branchOpsPull(ref: String, rebase: Bool) async throws {
        let parts = ref.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2, !parts[1].isEmpty else {
            throw GitClientError.outputError("Invalid remote branch '\(ref)'")
        }
        try Self.requireRefNames(parts[0], parts[1])
        let mode = rebase ? "--rebase" : "--no-rebase"
        try await branchOpsCheckedRun(["-c", "core.editor=true", "pull", mode, "--end-of-options", parts[0], parts[1]])
    }

    func branchOpsSetUpstream(branch: String, upstream: String?) async throws {
        try Self.requireRefNames(branch, upstream)
        if let upstream {
            try await branchOpsCheckedRun(["branch", "--set-upstream-to=\(upstream)", "--end-of-options", branch])
        } else {
            try await branchOpsCheckedRun(["branch", "--unset-upstream", "--end-of-options", branch])
        }
    }

    func branchOpsUpdateBranch(name: String, upstream: String, isCurrent: Bool) async throws {
        let parts = upstream.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else {
            throw GitClientError.outputError("Invalid upstream branch '\(upstream)'")
        }
        let remote = parts[0]
        let remoteBranch = parts[1]
        try Self.requireRefNames(name, remote, remoteBranch)
        if isCurrent {
            try await branchOpsCheckedRun(["fetch", "--end-of-options", remote])
            try await branchOpsCheckedRun(["merge", "--ff-only", "--end-of-options", upstream])
        } else {
            try await branchOpsCheckedRun(["fetch", "--end-of-options", remote, "\(remoteBranch):\(name)"])
        }
    }

    func branchOpsAddWorktree(path: String, ref: String?) async throws {
        try Self.requireRefNames(ref)
        let directory = Self.worktreeDirectory(path)
        if let ref {
            try await branchOpsCheckedRun(["worktree", "add", "--end-of-options", directory, ref])
        } else {
            try await branchOpsCheckedRun(["worktree", "add", "--end-of-options", directory])
        }
    }

    static func worktreeDirectory(_ path: String) -> String {
        var directory = Substring(path)
        while directory.count > 1, directory.hasSuffix("/") {
            directory = directory.dropLast()
        }
        return String(directory)
    }

    func branchOpsPushTag(name: String, remote: String) async throws {
        try Self.requireRefNames(name, remote)
        try await branchOpsCheckedRun(["push", "--end-of-options", remote, "refs/tags/\(name)"])
    }

    private func branchOpsCreateCheckedOutBranch(name: String, from ref: String?, flag: String) async throws {
        try Self.requireRefNames(name, ref)
        try await branchOpsCheckedRun(["checkout", flag, name] + (ref.map { ["--end-of-options", $0] } ?? []))
    }

    private func branchOpsCreateUncheckedBranch(name: String, from ref: String?, flag: String?) async throws {
        try Self.requireRefNames(name, ref)
        try await branchOpsCheckedRun(
            ["branch"] + (flag.map { [$0] } ?? []) + ["--end-of-options", name] + (ref.map { [$0] } ?? [])
        )
    }

    @discardableResult
    private func branchOpsCheckedRun(_ arguments: [String]) async throws -> String {
        try await run(arguments: arguments)
    }
}
