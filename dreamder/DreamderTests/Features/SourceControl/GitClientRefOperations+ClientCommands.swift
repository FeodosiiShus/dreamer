import Foundation
@testable import Dreamder

nonisolated extension RefOperations {
    static func logCommit(hash: String, parents: [String] = []) -> GitLogCommit {
        GitLogCommit(
            hash: hash,
            parents: parents,
            authorName: "A",
            authorEmail: "a@x",
            date: Date(timeIntervalSince1970: 0),
            refs: [],
            subject: "s"
        )
    }

    static let tagOperations: [RefOperation] = [
        RefOperation(
            label: "createTag name",
            run: { client, name in try await client.createTag(name: name, at: "abc") },
            arguments: { name in
                [
                    ["check-ref-format", "refs/tags/\(name)"],
                    ["rev-parse", "-q", "--verify", "refs/tags/\(name)"],
                    ["tag", "--end-of-options", name, "abc"]
                ]
            }
        ),
        RefOperation(
            label: "createTag revision",
            run: { client, name in try await client.createTag(name: "v1", at: name) },
            arguments: { name in
                [
                    ["check-ref-format", "refs/tags/v1"],
                    ["rev-parse", "-q", "--verify", "refs/tags/v1"],
                    ["tag", "--end-of-options", "v1", name]
                ]
            }
        ),
        RefOperation(
            label: "createTag forced and annotated",
            run: { client, name in try await client.createTag(name: "v1", at: name, message: "m", force: true) },
            arguments: { name in
                [
                    ["check-ref-format", "refs/tags/v1"],
                    ["tag", "-f", "-a", "-m", "m", "--end-of-options", "v1", name]
                ]
            }
        )
    ]

    static let transferOperations: [RefOperation] = [
        RefOperation(
            label: "pushToRemote remote",
            run: { client, name in try await client.pushToRemote(remote: name, branch: "main") },
            arguments: { name in [["push", "--end-of-options", name, "main"]] }
        ),
        RefOperation(
            label: "pushToRemote branch with every flag",
            run: { client, name in
                try await client.pushToRemote(
                    remote: "origin",
                    branch: name,
                    setUpstream: true,
                    force: true,
                    tags: true
                )
            },
            arguments: { name in
                [["push", "--set-upstream", "--force", "--tags", "--end-of-options", "origin", name]]
            }
        ),
        RefOperation(
            label: "pullFromRemote remote",
            run: { client, name in try await client.pullFromRemote(remote: name, branch: "main") },
            arguments: { name in [["pull", "--no-rebase", "--end-of-options", name, "main"]] }
        ),
        RefOperation(
            label: "pullFromRemote branch",
            run: { client, name in try await client.pullFromRemote(remote: "origin", branch: name, rebase: true) },
            arguments: { name in [["pull", "--rebase", "--end-of-options", "origin", name]] }
        ),
        RefOperation(
            label: "addRemote name",
            run: { client, name in try await client.addRemote(name: name, location: "https://example.test/x.git") },
            arguments: { name in [["remote", "add", "--end-of-options", name, "https://example.test/x.git"]] }
        ),
        RefOperation(
            label: "addRemote location",
            run: { client, name in try await client.addRemote(name: "backup", location: name) },
            arguments: { name in [["remote", "add", "--end-of-options", "backup", name]] }
        )
    ]

    static let commitOperations: [RefOperation] = [
        RefOperation(
            label: "isCommitPublished",
            run: { client, name in _ = try await client.isCommitPublished(name) },
            arguments: { name in [["branch", "-r", "--contains=\(name)", "--format=%(refname:short)"]] }
        ),
        RefOperation(
            label: "cherryPick",
            run: { client, name in
                let commit = RefOperations.logCommit(hash: name)
                _ = try await client.cherryPick(commit: commit, addSuffix: false)
            },
            arguments: { name in [["rev-parse", "--git-dir"], ["cherry-pick", "--end-of-options", name]] }
        ),
        RefOperation(
            label: "cherryPick merge with suffix",
            run: { client, name in
                let commit = RefOperations.logCommit(hash: name, parents: ["p1", "p2"])
                _ = try await client.cherryPick(commit: commit, addSuffix: true)
            },
            arguments: { name in
                [["rev-parse", "--git-dir"], ["cherry-pick", "-x", "-m", "1", "--end-of-options", name]]
            }
        ),
        RefOperation(
            label: "getCommitHistory",
            run: { client, name in _ = try await client.getCommitHistory(branchName: name) },
            arguments: { name in
                [
                    [
                        "log", "--no-merges", "-z", "--pretty=%h¦%H¦%s¦%aN¦%ae¦%cn¦%ce¦%at¦%b¦%D¦",
                        "--end-of-options", name, "--"
                    ],
                    ["ls-remote", "--get-url"]
                ]
            }
        ),
        RefOperation(
            label: "getCommitChangedFiles",
            run: { client, name in _ = try await client.getCommitChangedFiles(commitSHA: name) },
            arguments: { name in
                [["diff-tree", "--no-commit-id", "--name-status", "-r", "--end-of-options", name]]
            }
        ),
        RefOperation(
            label: "logGraphMessage",
            run: { client, name in _ = try await client.logGraphMessage(hash: name) },
            arguments: { name in [["log", "-1", "--format=%B", "--end-of-options", name]] }
        ),
        RefOperation(
            label: "logGraphChangedFiles root commit",
            run: { client, name in
                _ = try await client.logGraphChangedFiles(commit: RefOperations.logCommit(hash: name))
            },
            arguments: { name in
                [["diff-tree", "--root", "--no-commit-id", "--name-status", "-r", "--end-of-options", name]]
            }
        ),
        RefOperation(
            label: "logGraphChangedFiles parent",
            run: { client, name in
                let commit = RefOperations.logCommit(hash: "h1", parents: [name])
                _ = try await client.logGraphChangedFiles(commit: commit)
            },
            arguments: { name in [["diff", "--name-status", "--end-of-options", name, "h1"]] }
        )
    ]
}
