import Foundation
@testable import Dreamder

nonisolated extension RefOperations {
    static let branchOperations: [RefOperation] = [
        RefOperation(
            label: "createBranch name",
            run: { client, name in try await client.branchOpsCreateBranch(name: name, from: nil) },
            arguments: { name in [["checkout", "-b", name]] }
        ),
        RefOperation(
            label: "createBranch from",
            run: { client, name in try await client.branchOpsCreateBranch(name: "x", from: name) },
            arguments: { name in [["checkout", "-b", "x", "--end-of-options", name]] }
        ),
        RefOperation(
            label: "createBranch overwrite",
            run: { client, name in try await client.branchOpsCreateBranch(name: name, from: nil, overwrite: true) },
            arguments: { name in [["checkout", "-B", name]] }
        ),
        RefOperation(
            label: "createBranch without checkout name",
            run: { client, name in try await client.branchOpsCreateBranch(name: name, from: nil, checkout: false) },
            arguments: { name in [["branch", "--end-of-options", name]] }
        ),
        RefOperation(
            label: "createBranch without checkout from",
            run: { client, name in try await client.branchOpsCreateBranch(name: "x", from: name, checkout: false) },
            arguments: { name in [["branch", "--end-of-options", "x", name]] }
        ),
        RefOperation(
            label: "createBranch without checkout overwrite",
            run: { client, name in
                try await client.branchOpsCreateBranch(name: name, from: nil, checkout: false, overwrite: true)
            },
            arguments: { name in [["branch", "-f", "--end-of-options", name]] }
        ),
        RefOperation(
            label: "renameBranch old name",
            run: { client, name in try await client.branchOpsRenameBranch(oldName: name, newName: "x") },
            arguments: { name in [["branch", "-m", "--end-of-options", name, "x"]] }
        ),
        RefOperation(
            label: "renameBranch new name",
            run: { client, name in try await client.branchOpsRenameBranch(oldName: "x", newName: name) },
            arguments: { name in [["branch", "-m", "--end-of-options", "x", name]] }
        ),
        RefOperation(
            label: "renameBranch unset upstream",
            run: { client, name in
                try await client.branchOpsRenameBranch(oldName: "x", newName: name, unsetUpstream: true)
            },
            arguments: { name in
                [
                    ["branch", "-m", "--end-of-options", "x", name],
                    ["branch", "--unset-upstream", "--end-of-options", name]
                ]
            }
        ),
        RefOperation(
            label: "deleteLocalBranch",
            run: { client, name in try await client.branchOpsDeleteLocalBranch(name) },
            arguments: { name in [["branch", "-d", "--end-of-options", name]] }
        ),
        RefOperation(
            label: "deleteLocalBranch force",
            run: { client, name in try await client.branchOpsDeleteLocalBranch(name, force: true) },
            arguments: { name in [["branch", "-D", "--end-of-options", name]] }
        ),
        RefOperation(
            label: "restoreBranch name",
            run: { client, name in try await client.branchOpsRestoreBranch(name: name, at: "abc") },
            arguments: { name in [["branch", "--end-of-options", name, "abc"]] }
        ),
        RefOperation(
            label: "restoreBranch revision",
            run: { client, name in try await client.branchOpsRestoreBranch(name: "x", at: name) },
            arguments: { name in [["branch", "--end-of-options", "x", name]] }
        ),
        RefOperation(
            label: "setUpstream branch",
            run: { client, name in try await client.branchOpsSetUpstream(branch: name, upstream: "origin/x") },
            arguments: { name in [["branch", "--set-upstream-to=origin/x", "--end-of-options", name]] }
        ),
        RefOperation(
            label: "setUpstream upstream",
            run: { client, name in try await client.branchOpsSetUpstream(branch: "x", upstream: name) },
            arguments: { name in [["branch", "--set-upstream-to=\(name)", "--end-of-options", "x"]] }
        ),
        RefOperation(
            label: "unsetUpstream",
            run: { client, name in try await client.branchOpsSetUpstream(branch: name, upstream: nil) },
            arguments: { name in [["branch", "--unset-upstream", "--end-of-options", name]] }
        )
    ]

    static let remoteOperations: [RefOperation] = [
        RefOperation(
            label: "restoreTag name",
            run: { client, name in try await client.branchOpsRestoreTag(name: name, at: "abc") },
            arguments: { name in [["tag", "--end-of-options", name, "abc"]] }
        ),
        RefOperation(
            label: "restoreTag revision",
            run: { client, name in try await client.branchOpsRestoreTag(name: "v1", at: name) },
            arguments: { name in [["tag", "--end-of-options", "v1", name]] }
        ),
        RefOperation(
            label: "deleteTag",
            run: { client, name in try await client.branchOpsDeleteTag(name) },
            arguments: { name in [["tag", "-d", "--end-of-options", name]] }
        ),
        RefOperation(
            label: "deleteRemoteBranch remote",
            run: { client, name in try await client.branchOpsDeleteRemoteBranch(remote: name, branch: "x") },
            arguments: { name in [["push", "--delete", "--end-of-options", name, "x"]] }
        ),
        RefOperation(
            label: "deleteRemoteBranch branch",
            run: { client, name in try await client.branchOpsDeleteRemoteBranch(remote: "origin", branch: name) },
            arguments: { name in [["push", "--delete", "--end-of-options", "origin", name]] }
        ),
        RefOperation(
            label: "pushTag name",
            run: { client, name in try await client.branchOpsPushTag(name: name, remote: "origin") },
            arguments: { name in [["push", "--end-of-options", "origin", "refs/tags/\(name)"]] }
        ),
        RefOperation(
            label: "pushTag remote",
            run: { client, name in try await client.branchOpsPushTag(name: "v1", remote: name) },
            arguments: { name in [["push", "--end-of-options", name, "refs/tags/v1"]] }
        ),
        RefOperation(
            label: "pull remote",
            run: { client, name in try await client.branchOpsPull(ref: "\(name)/x", rebase: false) },
            arguments: { name in
                [["-c", "core.editor=true", "pull", "--no-rebase", "--end-of-options", name, "x"]]
            }
        ),
        RefOperation(
            label: "pull branch",
            run: { client, name in try await client.branchOpsPull(ref: "origin/\(name)", rebase: true) },
            arguments: { name in
                [["-c", "core.editor=true", "pull", "--rebase", "--end-of-options", "origin", name]]
            }
        ),
        RefOperation(
            label: "updateBranch name",
            run: { client, name in
                try await client.branchOpsUpdateBranch(name: name, upstream: "origin/x", isCurrent: false)
            },
            arguments: { name in [["fetch", "--end-of-options", "origin", "x:\(name)"]] }
        ),
        RefOperation(
            label: "updateBranch remote branch",
            run: { client, name in
                try await client.branchOpsUpdateBranch(name: "x", upstream: "origin/\(name)", isCurrent: false)
            },
            arguments: { name in [["fetch", "--end-of-options", "origin", "\(name):x"]] }
        ),
        RefOperation(
            label: "updateBranch current remote",
            run: { client, name in
                try await client.branchOpsUpdateBranch(name: "x", upstream: "\(name)/x", isCurrent: true)
            },
            arguments: { name in
                [["fetch", "--end-of-options", name], ["merge", "--ff-only", "--end-of-options", "\(name)/x"]]
            }
        ),
        RefOperation(
            label: "addWorktree",
            run: { client, name in try await client.branchOpsAddWorktree(path: "/tmp/wt", ref: name) },
            arguments: { name in [["worktree", "add", "--end-of-options", "/tmp/wt", name]] }
        )
    ]
}
