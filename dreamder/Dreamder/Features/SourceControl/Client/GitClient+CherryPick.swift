import Foundation

nonisolated enum GitCherryPickOutcome: Equatable, Sendable {
    case success
    case conflicts
    case empty
}

nonisolated extension GitBranchOperationState {
    var ongoingOperationName: String? {
        if isMerging { return "merge" }
        if isRebasing { return "rebase" }
        if isCherryPicking { return "cherry-pick" }
        if isReverting { return "revert" }
        return nil
    }
}

nonisolated extension GitClient {
    static let protectedBranchNames: Set<String> = ["master", "main"]

    func isCommitPublished(_ hash: String) async throws -> Bool {
        let output = try await run(arguments: ["branch", "-r", "--contains", hash, "--format=%(refname:short)"])
        return output
            .split(whereSeparator: \.isNewline)
            .contains { reference in
                let parts = reference.split(separator: "/", maxSplits: 1)
                return parts.count == 2 && Self.protectedBranchNames.contains(String(parts[1]))
            }
    }

    func cherryPick(
        commit: GitLogCommit,
        addSuffix: Bool,
        mainlineParent: Int = 1
    ) async throws -> GitCherryPickOutcome {
        let state = await branchOpsOperationState()
        if let operation = state.ongoingOperationName {
            throw GitClientError.outputError("Cannot cherry-pick during \(operation)")
        }
        var arguments = ["cherry-pick"]
        if addSuffix {
            arguments.append("-x")
        }
        if commit.isMerge {
            arguments += ["-m", String(mainlineParent)]
        }
        arguments.append(commit.hash)
        let result = try await runResult(arguments: arguments)
        if result.success {
            return .success
        }
        if Self.isEmptyCherryPick(result) {
            _ = try await run(arguments: ["cherry-pick", "--skip"])
            return .empty
        }
        let stateAfter = await branchOpsOperationState()
        if stateAfter.isCherryPicking || result.combinedText.contains("CONFLICT") {
            return .conflicts
        }
        throw Self.error(for: result)
    }

    static func isEmptyCherryPick(_ result: GitCommandResult) -> Bool {
        let text = result.combinedText
        return text.contains("nothing to commit")
            || text.contains("nothing added to commit but untracked files present")
            || text.contains("previous cherry-pick is now empty")
    }
}
