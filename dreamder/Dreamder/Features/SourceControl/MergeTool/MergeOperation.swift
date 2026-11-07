import Foundation

nonisolated enum MergeOperation: Equatable, Sendable {
    case merge(source: String, target: String)
    case rebase(branch: String, onto: String)
    case cherryPick(hash: String)
    case stash(branch: String)
    case unknown
}

nonisolated struct MergeRepositoryState: Equatable, Sendable {
    var currentBranch: String = ""
    var mergeSource: String?
    var rebaseBranch: String?
    var rebaseOnto: String?
    var hasRebaseInProgress: Bool = false
    var cherryPickHash: String?
    var hasStash: Bool = false
}

nonisolated struct MergeConflictContext: Equatable, Sendable {
    let operation: MergeOperation
    let yoursLabel: String
    let theirsLabel: String
    let summary: String

    var swapsSides: Bool {
        if case .rebase = operation {
            return true
        }
        return false
    }

    var yoursHeader: String { "Yours (\(yoursLabel))" }

    var theirsHeader: String { "Theirs (\(theirsLabel))" }

    static func make(from state: MergeRepositoryState) -> MergeConflictContext {
        let branch = state.currentBranch.isEmpty ? "HEAD" : state.currentBranch

        if let source = state.mergeSource, !source.isEmpty {
            return MergeConflictContext(
                operation: .merge(source: source, target: branch),
                yoursLabel: branch,
                theirsLabel: source,
                summary: "Merging branch \(source) into branch \(branch)"
            )
        }

        if state.hasRebaseInProgress || state.rebaseBranch != nil {
            let rebasing = state.rebaseBranch.flatMap { $0.isEmpty ? nil : $0 } ?? branch
            let onto = state.rebaseOnto.flatMap { $0.isEmpty ? nil : $0 } ?? "HEAD"
            return MergeConflictContext(
                operation: .rebase(branch: rebasing, onto: onto),
                yoursLabel: rebasing,
                theirsLabel: onto,
                summary: "Rebasing branch \(rebasing) onto \(onto)"
            )
        }

        if let hash = state.cherryPickHash, !hash.isEmpty {
            return MergeConflictContext(
                operation: .cherryPick(hash: hash),
                yoursLabel: branch,
                theirsLabel: hash,
                summary: "Cherry-picking \(hash) into branch \(branch)"
            )
        }

        if state.hasStash {
            return MergeConflictContext(
                operation: .stash(branch: branch),
                yoursLabel: branch,
                theirsLabel: "stash",
                summary: "Conflicts during unstashing"
            )
        }

        return MergeConflictContext(
            operation: .unknown,
            yoursLabel: branch,
            theirsLabel: "Theirs",
            summary: "The following files have conflicts:"
        )
    }
}
