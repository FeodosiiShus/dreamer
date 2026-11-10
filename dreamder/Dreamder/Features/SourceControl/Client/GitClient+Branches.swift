//
//  GitClient+Branches.swift
//  Dreamder
//
//  Created by Albert Vinizhanau on 10/20/23.
//

import Foundation

nonisolated extension GitClient {
    /// Get branches
    /// - Parameter remote: If passed, fetches branches for the specified remote
    /// - Returns: Array of branches
    @concurrent
    func getBranches(remote: String? = nil) async throws -> [GitBranch] {
        let output = try await run(arguments: [
            "branch",
            "--format=%(refname:short)|%(refname)|%(upstream:short) %(upstream:track)",
            remote != nil ? "-r" : "-a"
        ])

        let remotePrefix = remote.map { "\($0)/" }

        return output
            .components(separatedBy: "\n")
            .filter { line in
                guard line != "" else { return false }
                guard let remotePrefix else { return true }
                return line.starts(with: remotePrefix)
            }
            .map { line in
                let branchPart = String(line.prefix { $0 != " " })
                let branchComponents = branchPart.components(separatedBy: "|")
                let name = String(branchPart.prefix { $0 != "|" })
                let upstream = Self.field(at: 2, in: branchComponents)

                let trackInfoString = line
                    .dropFirst(branchPart.count)
                    .trimmingCharacters(in: .whitespacesWithoutNewlines)
                let trackInfo = Self.parseBranchTrackInfo(from: trackInfoString)

                return GitBranch(
                    name: remote.map { extractBranchName(from: name, with: $0) } ?? name,
                    longName: Self.field(at: 1, in: branchComponents) ?? name,
                    upstream: upstream?.isEmpty == true ? nil : upstream,
                    ahead: trackInfo.ahead,
                    behind: trackInfo.behind
                )
            }
            .filter { Self.isListedBranch(longName: $0.longName) }
    }

    /// Get current branch
    func getCurrentBranch() async throws -> GitBranch? {
        let branchName = try await run(arguments: ["branch", "--show-current"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !branchName.isEmpty else { return nil }
        let output = try await run(arguments: [
            "for-each-ref",
            "--format=%(refname)|%(upstream:short) %(upstream:track)",
            "refs/heads/\(branchName)"
        ])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let branchPart = String(output.prefix { $0 != " " })
        let branchComponents = branchPart.components(separatedBy: "|")
        let longName = String(branchPart.prefix { $0 != "|" })
        let upstream = Self.field(at: 1, in: branchComponents)

        let trackInfoString = output
            .dropFirst(branchPart.count)
            .trimmingCharacters(in: .whitespacesWithoutNewlines)
        let trackInfo = Self.parseBranchTrackInfo(from: trackInfoString)

        return .init(
            name: branchName,
            longName: longName,
            upstream: upstream?.isEmpty == true ? nil : upstream,
            ahead: trackInfo.ahead,
            behind: trackInfo.behind
        )
    }

    func getHeadCommit() async -> String? {
        guard let output = try? await run(arguments: ["rev-parse", "--verify", "--quiet", "HEAD"]) else {
            return nil
        }
        let commit = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return commit.isEmpty ? nil : commit
    }

    /// Checkout branch
    /// - Parameter branch: Branch to checkout
    func checkoutBranch(_ branch: GitBranch, forceLocal: Bool = false, newName: String? = nil) async throws {
        var arguments = ["checkout"]

        let remoteReference = branch.longName.replacingOccurrences(of: "refs/remotes/", with: "")
        let remoteBranchName = remoteReference.split(separator: "/", maxSplits: 1).dropFirst().first.map(String.init)
            ?? remoteReference
        let targetName = newName ?? (branch.isRemote ? remoteBranchName : branch.name)

        try Self.requireRefNames(targetName, branch.name, remoteReference)

        if branch.isRemote, !forceLocal {
            arguments += ["-b", targetName, "--track", "--end-of-options", remoteReference]
        } else if newName != nil {
            arguments += ["-b", targetName, "--end-of-options", branch.name]
        } else {
            arguments += ["--end-of-options", targetName]
        }

        do {
            _ = try await run(arguments: arguments)
        } catch let error as GitClientError {
            // If branch is remote and command failed because branch already exists
            // try to switch to local branch
            if branch.isRemote, error.description.contains("already exists") {
                try await checkoutBranch(branch, forceLocal: true)
            } else {
                logger.error("Failed to checkout branch: \(error.description, privacy: .public)")
                throw error
            }
        }
    }

    static func isListedBranch(longName: String) -> Bool {
        let components = longName.split(separator: "/")
        let isRemoteHead = components.count == 4 && components[1] == "remotes" && components[3] == "HEAD"
        return longName.hasPrefix("refs/") && !isRemoteHead
    }

    static func parseBranchTrackInfo(from infoString: String) -> (ahead: Int, behind: Int) {
        guard let open = infoString.firstIndex(of: "["),
              let close = infoString[open...].firstIndex(of: "]") else {
            return (0, 0)
        }
        var ahead = 0
        var behind = 0
        for part in infoString[infoString.index(after: open)..<close].split(separator: ",") {
            let words = part.split(separator: " ")
            guard words.count == 2, let count = Int(words[1]) else { continue }
            switch words[0] {
            case "ahead": ahead = count
            case "behind": behind = count
            default: break
            }
        }
        return (ahead, behind)
    }

    private func extractBranchName(from fullBranchName: String, with remoteName: String) -> String {
        let prefix = "\(remoteName)/"
        return fullBranchName.hasPrefix(prefix) ? String(fullBranchName.dropFirst(prefix.count)) : fullBranchName
    }

}
