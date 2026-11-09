import Foundation

extension SourceControlManager {
    func gitLogCreateTag(name: String, at revision: String, message: String?, force: Bool) async throws {
        try await gitClient.createTag(name: name, at: revision, message: message, force: force)
        await branchOpsRefresh()
    }

    func gitLogCherryPick(_ commit: GitLogCommit) async throws -> GitCherryPickOutcome {
        let addSuffix = (try? await gitClient.isCommitPublished(commit.hash)) ?? false
        let outcome = try await gitClient.cherryPick(commit: commit, addSuffix: addSuffix)
        await branchOpsRefresh()
        if outcome == .conflicts {
            await MergeConflictsCenter.shared.refresh(manager: self)
        }
        return outcome
    }

    func gitLogLocalBranchNames() -> Set<String> {
        Set(branches.filter(\.isLocal).map(\.name))
    }
}
