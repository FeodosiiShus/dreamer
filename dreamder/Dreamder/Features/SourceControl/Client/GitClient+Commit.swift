//
//  GitClient+Commit.swift
//  Dreamder
//
//  Created by Albert Vinizhanau on 10/20/23.
//

import Foundation
import RegexBuilder

nonisolated extension GitClient {
    /// Commit files
    /// - Parameters:
    ///   - message: Commit message
    func commit(message: String, details: String?) async throws {
        var fullMessage = message
        if let details, !details.isEmpty {
            fullMessage += "\n\n" + details
        }

        _ = try await run(arguments: ["commit", "--message=\(fullMessage)"])
    }

    /// Add file to git
    /// - Parameter file: File to add
    func add(_ files: [URL]) async throws {
        _ = try await run(arguments: ["add", "--"] + files.map { $0.path(percentEncoded: false) })
    }

    /// Add file to git
    /// - Parameter file: File to add
    func reset(_ files: [URL]) async throws {
        _ = try await run(arguments: ["reset", "--"] + files.map { $0.path(percentEncoded: false) })
    }

    /// Returns tuple of unsynced commits both ahead and behind
    func numberOfUnsyncedCommits() async throws -> (ahead: Int, behind: Int) {
        let output = try await run(arguments: ["status", "-sb", "--porcelain=v2"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return try parseUnsyncedCommitsOutput(from: output)
    }

    func getCommitChangedFiles(commitSHA: String) async throws -> [GitChangedFile] {
        try Self.requireRefNames(commitSHA)
        let output = try await run(arguments: [
            "diff-tree", "--no-commit-id", "--name-status", "-r", "--end-of-options", commitSHA
        ])
        return output
            .trimmingCharacters(in: .newlines)
            .components(separatedBy: "\n")
            .compactMap { line -> GitChangedFile? in
                let components = line.split(separator: "\t")
                guard components.count == 2 else { return nil }
                let changeType = String(components[0])
                let pathName = String(components[1])

                let gitType: GitStatus? = .init(rawValue: changeType)

                return GitChangedFile(
                    status: gitType ?? .none,
                    stagedStatus: .none,
                    fileURL: directoryURL.appending(path: pathName),
                    originalFilename: nil
                )
            }
    }

    private func parseUnsyncedCommitsOutput(from string: String) throws -> (ahead: Int, behind: Int) {
        let components = string.components(separatedBy: .newlines)
        guard var abLine = components.first(where: { $0.starts(with: "# branch.ab") }) else {
            // We're using --porcelain, this shouldn't happen
            return (ahead: 0, behind: 0)
        }
        abLine = String(abLine.dropFirst("# branch.ab ".count))
        let regex = Regex {
            One("+")
            Capture {
                OneOrMore(.digit)
            } transform: { Int($0) }
            One(" -")
            Capture {
                OneOrMore(.digit)
            } transform: { Int($0) }
        }
        guard let match = try regex.firstMatch(in: abLine),
              let ahead = match.output.1,
              let behind = match.output.2 else {
            return (ahead: 0, behind: 0)
        }
        return (ahead: ahead, behind: behind)
    }
}
