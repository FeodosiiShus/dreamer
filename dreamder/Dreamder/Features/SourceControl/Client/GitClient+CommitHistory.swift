//
//  GitClient+CommitHistory.swift
//  Dreamder
//
//  Created by Albert Vinizhanau on 10/20/23.
//

import Foundation

nonisolated extension GitClient {
    /// Gets the commit history log for the specified branch or file
    /// - Parameters:
    ///   - branchName: Name of the branch
    ///   - maxCount: Maximum amount of entries to get
    ///   - fileLocalPath: Optional path of file to get history for
    /// - Returns: Array of git commits
    @concurrent
    func getCommitHistory(
        branchName: String? = nil,
        maxCount: Int? = nil,
        fileLocalPath: String? = nil,
        showMergeCommits: Bool = false
    ) async throws -> [GitCommit] {
        var arguments = ["log"]
        if !showMergeCommits {
            arguments.append("--no-merges")
        }
        arguments += ["-z", "--pretty=%h¦%H¦%s¦%aN¦%ae¦%cn¦%ce¦%at¦%b¦%D¦"]
        if let maxCount {
            arguments += ["-n", "\(maxCount)"]
        }
        if let branchName {
            arguments.append(branchName)
        }
        arguments.append("--")
        if let fileLocalPath {
            arguments.append(fileLocalPath)
        }

        let output = try await run(arguments: arguments)
        let remoteURL = try await getRemoteURL()

        return output
            .split(separator: "\0")
            .map { line -> GitCommit in
                let parameters = String(line).components(separatedBy: "¦")
                let infoRef = Self.field(at: 9, in: parameters)
                var refs: [String] = []
                var tag = ""
                if let infoRef = infoRef {
                    if infoRef.contains("tag:") {
                        tag = infoRef.components(separatedBy: "tag:")[1].trimmingCharacters(in: .whitespaces)
                    } else {
                        refs = infoRef.split(separator: ",").compactMap {
                            var element = String($0)
                            if element.contains("origin/HEAD") { return nil }
                            if element.contains("HEAD -> ") {
                                element = element.replacingOccurrences(of: "HEAD -> ", with: "")
                            }
                            return element.trimmingCharacters(in: .whitespaces)
                        }
                    }
                }

                return GitCommit(
                    hash: Self.field(at: 0, in: parameters) ?? "",
                    commitHash: Self.field(at: 1, in: parameters) ?? "",
                    message: Self.field(at: 2, in: parameters) ?? "",
                    author: Self.field(at: 3, in: parameters) ?? "",
                    authorEmail: Self.field(at: 4, in: parameters) ?? "",
                    committer: Self.field(at: 5, in: parameters) ?? "",
                    committerEmail: Self.field(at: 6, in: parameters) ?? "",
                    body: Self.field(at: 8, in: parameters) ?? "",
                    refs: refs,
                    tag: tag,
                    remoteURL: remoteURL,
                    date: Self.field(at: 7, in: parameters).flatMap { TimeInterval($0) }
                        .map { Date(timeIntervalSince1970: $0) } ?? Date()
                )
            }
    }
}
