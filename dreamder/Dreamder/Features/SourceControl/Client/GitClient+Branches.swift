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

        return output
            .components(separatedBy: "\n")
            .filter { $0 != "" && !$0.contains("HEAD") && (remote == nil || $0.starts(with: "\(remote ?? "")/")) }
            .compactMap { line in
                guard let branchPart = line.components(separatedBy: " ").first else { return nil }
                let branchComponents = branchPart.components(separatedBy: "|")
                guard let name = branchComponents.first else { return nil }
                let upstream = Self.field(at: 2, in: branchComponents)

                let trackInfoString = line
                    .dropFirst(branchPart.count)
                    .trimmingCharacters(in: .whitespacesWithoutNewlines)
                let trackInfo = Self.parseBranchTrackInfo(from: trackInfoString)

                return GitBranch(
                    name: remote != nil ? extractBranchName(from: name, with: remote ?? "") : name,
                    longName: Self.field(at: 1, in: branchComponents) ?? name,
                    upstream: upstream?.isEmpty == true ? nil : upstream,
                    ahead: trackInfo.ahead,
                    behind: trackInfo.behind
                )
            }
    }

    /// Get current branch
    func getCurrentBranch() async throws -> GitBranch? {
        let branchName = try await run(arguments: ["branch", "--show-current"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let output = try await run(arguments: [
            "for-each-ref",
            "--format=%(refname)|%(upstream:short) %(upstream:track)",
            "refs/heads/\(branchName)"
        ])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let branchPart = output.components(separatedBy: " ").first else { return nil }
        let branchComponents = branchPart.components(separatedBy: "|")
        guard let longName = branchComponents.first else { return nil }
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

    /// Delete branch
    func deleteBranch(_ branch: GitBranch) async throws {
        if !branch.isLocal {
            return
        }

        _ = try await run(arguments: ["branch", "-d", branch.name])
    }

    /// Rename branch
    /// - Parameter from: Name of the branch to rename
    /// - Parameter to: New name for branch
    func renameBranch(oldName: String, newName: String) async throws {
        _ = try await run(arguments: ["branch", "-m", oldName, newName])
    }

    /// Checkout branch
    /// - Parameter branch: Branch to checkout
    func checkoutBranch(_ branch: GitBranch, forceLocal: Bool = false, newName: String? = nil) async throws {
        var arguments = ["checkout"]

        let targetName = newName ?? branch.name

        if (branch.isRemote && !forceLocal) || newName != nil {
            let sourceBranch = branch.isRemote
                ? branch.longName.replacingOccurrences(of: "refs/remotes/", with: "")
                : branch.name
            arguments += ["-b", targetName, sourceBranch]
        } else {
            arguments.append(targetName)
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
        // Ensure the fullBranchName starts with the remoteName followed by a slash
        let prefix = "\(remoteName)/"
        if fullBranchName.hasPrefix(prefix) {
            // Remove the remoteName and the slash to get the branch name
            return String(fullBranchName.dropFirst(prefix.count))
        } else {
            // If the fullBranchName does not start with the expected remoteName, return it unchanged
            return fullBranchName
        }
    }

}
