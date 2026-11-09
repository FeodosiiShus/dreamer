import Foundation
import Testing
@testable import Dreamder

nonisolated struct RefOperation: Sendable, CustomTestStringConvertible {
    let label: String
    let run: @Sendable (GitClient, String) async throws -> Void
    let arguments: @Sendable (String) -> [[String]]

    var testDescription: String { label }
}

nonisolated enum RefOperations {
    static let hostileNames = ["-f", "--upload-pack=x", "-"]
    static let spacedNames = ["my feature", "a b"]

    static let all: [RefOperation] = checkoutOperations + historyOperations + branchOperations + remoteOperations
        + tagOperations + transferOperations + commitOperations

    static func localBranch(_ name: String) -> GitBranch {
        GitBranch(name: name, longName: "refs/heads/\(name)", upstream: nil, ahead: 0, behind: 0)
    }

    static func remoteBranch(_ name: String) -> GitBranch {
        GitBranch(name: "origin/\(name)", longName: "refs/remotes/origin/\(name)", upstream: nil, ahead: 0, behind: 0)
    }
}

nonisolated extension RefOperations {
    static let checkoutOperations: [RefOperation] = [
        RefOperation(
            label: "checkoutLocal",
            run: { client, name in try await client.branchOpsCheckoutLocal(name) },
            arguments: { name in [["checkout", "--end-of-options", name]] }
        ),
        RefOperation(
            label: "checkoutRevision",
            run: { client, name in try await client.branchOpsCheckoutRevision(name) },
            arguments: { name in [["checkout", "--end-of-options", name]] }
        ),
        RefOperation(
            label: "checkoutRemote local part",
            run: { client, name in try await client.branchOpsCheckoutRemote("origin/\(name)") },
            arguments: { name in
                [
                    ["rev-parse", "-q", "--verify", "refs/heads/\(name)"],
                    ["checkout", "--track", "-b", name, "--end-of-options", "origin/\(name)"]
                ]
            }
        ),
        RefOperation(
            label: "checkoutRemote remote part",
            run: { client, name in try await client.branchOpsCheckoutRemote("\(name)/x") },
            arguments: { name in
                [
                    ["rev-parse", "-q", "--verify", "refs/heads/x"],
                    ["checkout", "--track", "-b", "x", "--end-of-options", "\(name)/x"]
                ]
            }
        ),
        RefOperation(
            label: "checkoutRemoteTrackingBranch local name",
            run: { client, name in
                try await client.branchOpsCheckoutRemoteTrackingBranch(localName: name, remote: "origin/x")
            },
            arguments: { name in [["checkout", "--track", "-b", name, "--end-of-options", "origin/x"]] }
        ),
        RefOperation(
            label: "checkoutRemoteTrackingBranch remote",
            run: { client, name in
                try await client.branchOpsCheckoutRemoteTrackingBranch(localName: "x", remote: name)
            },
            arguments: { name in [["checkout", "--track", "-b", "x", "--end-of-options", name]] }
        ),
        RefOperation(
            label: "checkoutRemoteTrackingBranch overwrite",
            run: { client, name in
                try await client.branchOpsCheckoutRemoteTrackingBranch(
                    localName: name,
                    remote: "origin/x",
                    overwrite: true
                )
            },
            arguments: { name in [["checkout", "-B", name, "--end-of-options", "origin/x"]] }
        ),
        RefOperation(
            label: "resetLocalBranchToRemote local name",
            run: { client, name in
                try await client.branchOpsResetLocalBranchToRemote(localName: name, remote: "origin/x")
            },
            arguments: { name in [["checkout", "-B", name, "--end-of-options", "origin/x"]] }
        ),
        RefOperation(
            label: "resetLocalBranchToRemote remote",
            run: { client, name in
                try await client.branchOpsResetLocalBranchToRemote(localName: "x", remote: name)
            },
            arguments: { name in [["checkout", "-B", "x", "--end-of-options", name]] }
        ),
        RefOperation(
            label: "checkoutAndRebase branch",
            run: { client, name in _ = try await client.branchOpsCheckoutAndRebase(name, onto: "main") },
            arguments: { name in
                [
                    ["checkout", "--end-of-options", name],
                    ["rebase", "--end-of-options", "main"],
                    ["rev-parse", "--git-dir"]
                ]
            }
        ),
        RefOperation(
            label: "checkoutAndRebase onto",
            run: { client, name in _ = try await client.branchOpsCheckoutAndRebase("main", onto: name) },
            arguments: { name in
                [
                    ["checkout", "--end-of-options", "main"],
                    ["rebase", "--end-of-options", name],
                    ["rev-parse", "--git-dir"]
                ]
            }
        ),
        RefOperation(
            label: "checkoutBranch local",
            run: { client, name in try await client.checkoutBranch(RefOperations.localBranch(name)) },
            arguments: { name in [["checkout", "--end-of-options", name]] }
        ),
        RefOperation(
            label: "checkoutBranch new name",
            run: { client, name in
                try await client.checkoutBranch(RefOperations.localBranch("main"), newName: name)
            },
            arguments: { name in [["checkout", "-b", name, "--end-of-options", "main"]] }
        ),
        RefOperation(
            label: "checkoutBranch remote",
            run: { client, name in try await client.checkoutBranch(RefOperations.remoteBranch(name)) },
            arguments: { name in [["checkout", "-b", name, "--track", "--end-of-options", "origin/\(name)"]] }
        )
    ]

    static let historyOperations: [RefOperation] = [
        RefOperation(
            label: "revision",
            run: { client, name in _ = try await client.branchOpsRevision(name) },
            arguments: { name in [["rev-parse", "--verify", "--end-of-options", name]] }
        ),
        RefOperation(
            label: "commitCount branch",
            run: { client, name in _ = try await client.branchOpsCommitCount(branch: name, notIn: "main") },
            arguments: { name in [["rev-list", "--count", "--end-of-options", "main..\(name)"]] }
        ),
        RefOperation(
            label: "commitCount base",
            run: { client, name in _ = try await client.branchOpsCommitCount(branch: "main", notIn: name) },
            arguments: { name in [["rev-list", "--count", "--end-of-options", "\(name)..main"]] }
        ),
        RefOperation(
            label: "commits branch",
            run: { client, name in _ = try await client.branchOpsCommits(branch: name, notIn: "main") },
            arguments: { name in
                [["log", "--format=%h|%s|%an|%ad", "--date=short", "--end-of-options", "main..\(name)"]]
            }
        ),
        RefOperation(
            label: "commits base",
            run: { client, name in _ = try await client.branchOpsCommits(branch: "main", notIn: name) },
            arguments: { name in
                [["log", "--format=%h|%s|%an|%ad", "--date=short", "--end-of-options", "\(name)..main"]]
            }
        ),
        RefOperation(
            label: "unmergedCommits branch",
            run: { client, name in _ = try await client.branchOpsUnmergedCommits(branch: name, base: "main") },
            arguments: { name in [["log", "--format=%h  %s", "--end-of-options", "main..\(name)"]] }
        ),
        RefOperation(
            label: "unmergedCommits base",
            run: { client, name in _ = try await client.branchOpsUnmergedCommits(branch: "main", base: name) },
            arguments: { name in [["log", "--format=%h  %s", "--end-of-options", "\(name)..main"]] }
        ),
        RefOperation(
            label: "merge",
            run: { client, name in _ = try await client.branchOpsMerge(name) },
            arguments: { name in
                [
                    ["-c", "core.editor=true", "merge", "--no-edit", "--end-of-options", name],
                    ["rev-parse", "--git-dir"]
                ]
            }
        ),
        RefOperation(
            label: "rebase",
            run: { client, name in _ = try await client.branchOpsRebase(onto: name) },
            arguments: { name in [["rebase", "--end-of-options", name], ["rev-parse", "--git-dir"]] }
        )
    ]
}
