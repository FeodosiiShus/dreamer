import Foundation

struct GitBranchOperationState: Hashable {
    var isMerging = false
    var isRebasing = false
    var isCherryPicking = false
    var isReverting = false

    static let none = GitBranchOperationState()

    var hasOngoingOperation: Bool {
        isMerging || isRebasing || isCherryPicking || isReverting
    }
}

extension GitClient {
    func branchOpsListTags() async throws -> [GitTag] {
        let output = try await run("for-each-ref --format=\"%(refname:short)|%(objectname:short)\" refs/tags")
        return GitTag.list(from: output)
    }

    func branchOpsRecentBranchNames(limit: Int) async throws -> [String] {
        let safeLimit = max(limit, 1) * 4
        let output = try await run("reflog --format=%gs -n \(safeLimit)")
        return BranchesPopupReflogParser.recentBranchNames(from: output, limit: limit)
    }

    func branchOpsOperationState() async -> GitBranchOperationState {
        guard let gitDirectory = try? await run("rev-parse --git-dir")
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

    func branchOpsRevision(_ revision: String) async throws -> String {
        try await run("rev-parse \(branchOpsQuote(revision))")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func branchOpsBranchExists(_ name: String) async throws -> Bool {
        let output = try await run("rev-parse -q --verify \(branchOpsQuote("refs/heads/\(name)"))")
        return !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func branchOpsCheckoutLocal(_ name: String) async throws {
        try await branchOpsCheckedRun("checkout \(branchOpsQuote(name))")
    }

    func branchOpsCheckoutRemote(_ shortName: String) async throws {
        let parts = shortName.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2, !parts[1].isEmpty else {
            throw GitClientError.outputError("Invalid remote branch '\(shortName)'")
        }
        let localName = parts[1]
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
        let flag = overwrite ? "-B" : "--track -b"
        try await branchOpsCheckedRun(
            "checkout \(flag) \(branchOpsQuote(localName)) \(branchOpsQuote(remote))"
        )
    }

    func branchOpsResetLocalBranchToRemote(localName: String, remote: String) async throws {
        try await branchOpsCheckedRun("checkout -B \(branchOpsQuote(localName)) \(branchOpsQuote(remote))")
    }

    func branchOpsCommitCount(branch: String, notIn base: String) async throws -> Int {
        let output = try await branchOpsCheckedRun("rev-list --count \(branchOpsQuote("\(base)..\(branch)"))")
        return Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    func branchOpsCommits(branch: String, notIn base: String) async throws -> [BranchesCompareCommit] {
        let output = try await run(
            "log --format=\"%h|%s|%an|%ad\" --date=short \(branchOpsQuote("\(base)..\(branch)"))"
        )
        return BranchesCompareCommit.list(from: output)
    }

    func branchOpsCheckoutRevision(_ revision: String) async throws {
        try await branchOpsCheckedRun("checkout \(branchOpsQuote(revision))")
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
        try await branchOpsCheckedRun(
            "branch -m \(branchOpsQuote(oldName)) \(branchOpsQuote(newName))"
        )
        if unsetUpstream {
            try await branchOpsCheckedRun("branch --unset-upstream \(branchOpsQuote(newName))")
        }
    }

    func branchOpsDeleteLocalBranch(_ name: String, force: Bool = false) async throws {
        let output = try await run("branch \(force ? "-D" : "-d") \(branchOpsQuote(name))")
        if !force, output.contains("not fully merged") || output.contains("not merged") {
            throw GitClientError.branchNotFullyMerged
        }
        if let failure = branchOpsFailure(in: output) {
            throw GitClientError.outputError(failure)
        }
    }

    func branchOpsUnmergedCommits(branch: String, base: String) async throws -> [String] {
        let output = try await run(
            "log --format=\"%h  %s\" \(branchOpsQuote("\(base)..\(branch)"))"
        )
        return output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    func branchOpsRestoreBranch(name: String, at revision: String) async throws {
        try await branchOpsCheckedRun("branch \(branchOpsQuote(name)) \(branchOpsQuote(revision))")
    }

    func branchOpsRestoreTag(name: String, at revision: String) async throws {
        try await branchOpsCheckedRun("tag \(branchOpsQuote(name)) \(branchOpsQuote(revision))")
    }

    func branchOpsDeleteRemoteBranch(remote: String, branch: String) async throws {
        try await branchOpsCheckedRun("push \(branchOpsQuote(remote)) --delete \(branchOpsQuote(branch))")
    }

    func branchOpsDeleteTag(_ name: String) async throws {
        try await branchOpsCheckedRun("tag -d \(branchOpsQuote(name))")
    }

    func branchOpsMerge(_ ref: String) async throws -> Bool {
        let output = try await run("-c core.editor=true merge --no-edit \(branchOpsQuote(ref))")
        let state = await branchOpsOperationState()
        if state.isMerging {
            return true
        }
        if output.contains("CONFLICT") {
            return true
        }
        if let failure = branchOpsFailure(in: output) {
            throw GitClientError.outputError(failure)
        }
        return false
    }

    func branchOpsRebase(onto ref: String) async throws -> Bool {
        let output = try await run("rebase \(branchOpsQuote(ref))")
        let state = await branchOpsOperationState()
        if state.isRebasing || output.contains("CONFLICT") || output.contains("could not apply") {
            return true
        }
        if let failure = branchOpsFailure(in: output) {
            throw GitClientError.outputError(failure)
        }
        return false
    }

    func branchOpsCheckoutAndRebase(_ branch: String, onto ref: String) async throws -> Bool {
        try await branchOpsCheckoutLocal(branch)
        return try await branchOpsRebase(onto: ref)
    }

    func branchOpsRebaseAbort() async throws {
        try await branchOpsCheckedRun("rebase --abort")
    }

    func branchOpsRebaseContinue() async throws {
        try await branchOpsCheckedRun("-c core.editor=true rebase --continue")
    }

    func branchOpsRebaseSkip() async throws {
        try await branchOpsCheckedRun("-c core.editor=true rebase --skip")
    }

    func branchOpsMergeAbort() async throws {
        try await branchOpsCheckedRun("merge --abort")
    }

    func branchOpsCherryPickAbort() async throws {
        try await branchOpsCheckedRun("cherry-pick --abort")
    }

    func branchOpsCherryPickContinue() async throws {
        try await branchOpsCheckedRun("-c core.editor=true cherry-pick --continue")
    }

    func branchOpsFetchAll() async throws {
        try await branchOpsCheckedRun("fetch --all --prune")
    }

    func branchOpsPullCurrent() async throws {
        try await branchOpsCheckedRun("pull --no-rebase")
    }

    func branchOpsPull(ref: String, rebase: Bool) async throws {
        let parts = ref.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2, !parts[1].isEmpty else {
            throw GitClientError.outputError("Invalid remote branch '\(ref)'")
        }
        let mode = rebase ? "--rebase" : "--no-rebase"
        try await branchOpsCheckedRun(
            "-c core.editor=true pull \(mode) \(branchOpsQuote(parts[0])) \(branchOpsQuote(parts[1]))"
        )
    }

    func branchOpsSetUpstream(branch: String, upstream: String?) async throws {
        if let upstream {
            try await branchOpsCheckedRun(
                "branch --set-upstream-to=\(branchOpsQuote(upstream)) \(branchOpsQuote(branch))"
            )
        } else {
            try await branchOpsCheckedRun("branch --unset-upstream \(branchOpsQuote(branch))")
        }
    }

    func branchOpsUpdateBranch(name: String, upstream: String, isCurrent: Bool) async throws {
        let parts = upstream.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else {
            throw GitClientError.outputError("Invalid upstream branch '\(upstream)'")
        }
        let remote = parts[0]
        let remoteBranch = parts[1]
        if isCurrent {
            try await branchOpsCheckedRun("fetch \(branchOpsQuote(remote))")
            try await branchOpsCheckedRun("merge --ff-only \(branchOpsQuote(upstream))")
        } else {
            try await branchOpsCheckedRun(
                "fetch \(branchOpsQuote(remote)) \(branchOpsQuote(remoteBranch)):\(branchOpsQuote(name))"
            )
        }
    }

    func branchOpsAddWorktree(path: String, ref: String?) async throws {
        if let ref {
            try await branchOpsCheckedRun(
                "worktree add \(branchOpsQuote(path)) \(branchOpsQuote(ref))"
            )
        } else {
            try await branchOpsCheckedRun("worktree add \(branchOpsQuote(path))")
        }
    }

    func branchOpsPushTag(name: String, remote: String) async throws {
        try await branchOpsCheckedRun(
            "push \(branchOpsQuote(remote)) \(branchOpsQuote("refs/tags/\(name)"))"
        )
    }

    private func branchOpsCreateCheckedOutBranch(name: String, from ref: String?, flag: String) async throws {
        if let ref {
            try await branchOpsCheckedRun(
                "checkout \(flag) \(branchOpsQuote(name)) \(branchOpsQuote(ref))"
            )
        } else {
            try await branchOpsCheckedRun("checkout \(flag) \(branchOpsQuote(name))")
        }
    }

    private func branchOpsCreateUncheckedBranch(name: String, from ref: String?, flag: String?) async throws {
        let prefix = flag.map { "branch \($0) " } ?? "branch "
        if let ref {
            try await branchOpsCheckedRun("\(prefix)\(branchOpsQuote(name)) \(branchOpsQuote(ref))")
        } else {
            try await branchOpsCheckedRun("\(prefix)\(branchOpsQuote(name))")
        }
    }

    @discardableResult
    private func branchOpsCheckedRun(_ command: String) async throws -> String {
        let output = try await run(command)
        if let failure = branchOpsFailure(in: output) {
            throw GitClientError.outputError(failure)
        }
        return output
    }

    private func branchOpsFailure(in output: String) -> String? {
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("fatal:")
                || trimmed.hasPrefix("error:")
                || trimmed.hasPrefix("! [rejected]")
                || trimmed.contains("Updates were rejected")
                || trimmed.hasPrefix("There is no tracking information")
                || trimmed.contains("has no upstream branch") {
                return trimmed
            }
        }
        return nil
    }

    private func branchOpsQuote(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
