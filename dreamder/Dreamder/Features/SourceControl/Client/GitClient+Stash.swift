//
//  GitClient+Stash.swift
//  Dreamder
//
//  Created by Austin Condiff on 11/20/23.
//

import Foundation

nonisolated extension GitClient {
    /// Add uncommited changes to stash
    func stash(message: String?) async throws {
        let arguments = message.map { ["stash", "push", "--message", $0] } ?? ["stash"]

        _ = try await self.run(arguments: arguments)
    }

    /// Pops the latest entry from stash onto HEAD
    func stashPop() async throws {
        _ = try await self.run(arguments: ["stash", "pop"])
    }

    /// Lists all of the entries in stash
    func stashList() async throws -> [GitStashEntry] {
        let output = try await run(arguments: ["stash", "list", "--format=%gd%x1f%ct%x1f%gs"])
        let stashEntries = parseGitStashEntries(output)

        return stashEntries
    }

    /// Apply stash
    func applyStashEntry(_ index: Int?) async throws {
        if let idx = index {
            _ = try await run(arguments: ["stash", "apply", "stash@{\(idx)}"])
        } else {
            _ = try await run(arguments: ["stash", "apply"])
        }
    }

    /// Delete stash
    func deleteStashEntry(_ index: Int) async throws {
        _ = try await run(arguments: ["stash", "drop", "stash@{\(index)}"])
    }
}

nonisolated func parseGitStashEntries(_ input: String) -> [GitStashEntry] {
    var entries: [GitStashEntry] = []

    let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
    let lines = trimmedInput.split(separator: "\n", omittingEmptySubsequences: false)

    for (index, line) in lines.enumerated() {
        let fields = line.split(separator: "\u{1f}", maxSplits: 2, omittingEmptySubsequences: false)
        guard fields.count == 3, let seconds = TimeInterval(fields[1]) else { continue }

        let subject = fields[2].split(separator: ": ", maxSplits: 1, omittingEmptySubsequences: true)
        guard subject.count == 2 else { continue }

        let message = subject[1].trimmingCharacters(in: .whitespaces)

        let entry = GitStashEntry(index: index, message: message, date: Date(timeIntervalSince1970: seconds))
        entries.append(entry)
    }

    return entries
}
