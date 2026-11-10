import Foundation

nonisolated struct GitGutterRepositorySignature: Equatable, Sendable {
    var isGitRepository = false
    var branchName: String?
    var headCommit: String?
    var ahead = 0
    var behind = 0
    var changedFiles: Set<GitChangedFile> = []
    var unsyncedAhead = 0
    var unsyncedBehind = 0

    @MainActor
    init(manager: SourceControlManager) {
        isGitRepository = manager.isGitRepository
        branchName = manager.currentBranch?.longName
        headCommit = manager.currentHeadCommit
        ahead = manager.currentBranch?.ahead ?? 0
        behind = manager.currentBranch?.behind ?? 0
        changedFiles = Set(manager.changedFiles)
        unsyncedAhead = manager.numberOfUnsyncedCommits.ahead
        unsyncedBehind = manager.numberOfUnsyncedCommits.behind
    }
}
