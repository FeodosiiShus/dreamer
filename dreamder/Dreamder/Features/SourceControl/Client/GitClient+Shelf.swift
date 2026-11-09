import Foundation

nonisolated struct GitShelfFile: Hashable, Sendable {
    let status: GitStatus
    let path: String
}

nonisolated struct GitShelf: Hashable, Sendable, Identifiable {
    static let marker = "Dreamder Shelf: "
    static let unnamed = "Unnamed"

    let index: Int
    let hash: String
    let name: String
    let date: Date
    let files: [GitShelfFile]

    var id: String { hash }

    static func normalizedName(_ name: String) -> String {
        let flattened = name
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return flattened.isEmpty ? unnamed : flattened
    }
}

nonisolated enum GitShelfUnshelveOutcome: Equatable, Sendable {
    case applied
    case conflicts
}

nonisolated enum GitShelfError: Error, Equatable, Sendable {
    case emptySelection
    case nothingToShelve
    case notFound
    case untrackedFileExists(String)
    case wouldOverwriteLocalChanges(String)
    case unsavedChanges(String)

    var message: String {
        switch self {
        case .emptySelection:
            "No changes selected to shelve"
        case .nothingToShelve:
            "The selected files have no local changes to shelve"
        case .notFound:
            "The shelf no longer exists"
        case .untrackedFileExists(let detail):
            "Cannot unshelve because untracked files already exist:\n\(detail)\n\nThe shelf was kept."
        case .wouldOverwriteLocalChanges(let detail):
            "Unshelving would overwrite local changes:\n\(detail)\n\nCommit, roll back or shelve them first. The shelf was kept."
        case .unsavedChanges(let detail):
            "These files have unsaved changes in the editor:\n\(detail)\n\n"
                + "Save or revert them first. Nothing was changed."
        }
    }

    static func classify(applyFailure text: String) -> GitShelfError? {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        let collisions = lines
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.contains("already exists") || $0.contains("could not restore untracked files") }
        if !collisions.isEmpty {
            return .untrackedFileExists(collisions.joined(separator: "\n"))
        }
        if text.contains("would be overwritten") {
            let files = lines
                .filter { $0.hasPrefix("\t") }
                .map { $0.trimmingCharacters(in: .whitespaces) }
            return .wouldOverwriteLocalChanges(files.joined(separator: "\n"))
        }
        return nil
    }
}

nonisolated struct GitShelfStashEntry: Equatable, Sendable {
    let index: Int
    let hash: String
    let date: Date
    let subject: String

    var shelfParts: (prefix: String, name: String)? {
        guard let separator = subject.range(of: ": ") else { return nil }
        let body = subject[separator.upperBound...]
        guard body.hasPrefix(GitShelf.marker) else { return nil }
        return (String(subject[..<separator.upperBound]), String(body.dropFirst(GitShelf.marker.count)))
    }

    static func parse(_ output: String) -> [GitShelfStashEntry] {
        output.split(separator: "\n", omittingEmptySubsequences: false).enumerated().compactMap { index, line -> GitShelfStashEntry? in
            let fields = line.split(separator: "\u{1f}", maxSplits: 2, omittingEmptySubsequences: false)
            guard fields.count == 3, let seconds = TimeInterval(fields[1]) else { return nil }
            return GitShelfStashEntry(
                index: index,
                hash: String(fields[0]),
                date: Date(timeIntervalSince1970: seconds),
                subject: String(fields[2])
            )
        }
    }
}

nonisolated extension GitClient {
    func shelfStashEntries() async throws -> [GitShelfStashEntry] {
        let output = try await run(arguments: ["stash", "list", "--format=%H%x1f%ct%x1f%gs"])
        return GitShelfStashEntry.parse(output)
    }

    func shelfList() async throws -> [GitShelf] {
        var shelves: [GitShelf] = []
        for entry in try await shelfStashEntries() {
            guard let parts = entry.shelfParts else { continue }
            let files = try await shelfFiles(of: entry.hash)
            shelves.append(GitShelf(index: entry.index, hash: entry.hash, name: parts.name, date: entry.date, files: files))
        }
        return shelves
    }

    func shelf(hash: String) async throws -> GitShelf {
        guard let shelf = try await shelfList().first(where: { $0.hash == hash }) else {
            throw GitShelfError.notFound
        }
        return shelf
    }

    func shelfFiles(of hash: String) async throws -> [GitShelfFile] {
        let output = try await run(arguments: [
            "stash", "show", "--include-untracked", "--name-status", "--no-renames", "-z", hash
        ])
        let tokens = output.split(separator: "\0", omittingEmptySubsequences: true)
        return stride(from: 0, to: tokens.count - 1, by: 2)
            .map { GitShelfFile(status: GitStatus(rawValue: String(tokens[$0].prefix(1))) ?? .modified, path: String(tokens[$0 + 1])) }
            .sorted { $0.path < $1.path }
    }

    func shelve(paths: [String], name: String) async throws -> GitShelf {
        guard !paths.isEmpty else { throw GitShelfError.emptySelection }
        let before = try await topStashHash()
        let literalPaths = paths.map { ":(literal)" + $0 }
        try await unstageDeletions(among: literalPaths)
        let arguments = ["stash", "push", "--include-untracked", "--message", GitShelf.marker + GitShelf.normalizedName(name), "--"]
            + literalPaths
        _ = try await run(arguments: arguments)
        guard let after = try await topStashHash(), after != before else {
            throw GitShelfError.nothingToShelve
        }
        return try await shelf(hash: after)
    }

    private func unstageDeletions(among literalPaths: [String]) async throws {
        let output = try await run(arguments: ["diff", "--cached", "--no-renames", "--diff-filter=D", "--name-only", "-z", "--"] + literalPaths)
        let deleted = output.split(separator: "\0", omittingEmptySubsequences: true).map { ":(literal)" + $0 }
        guard !deleted.isEmpty else { return }
        _ = try await run(arguments: ["reset", "-q", "--"] + deleted)
    }

    func unshelve(hash: String, keep: Bool) async throws -> GitShelfUnshelveOutcome {
        let reference = try await shelfReference(of: hash)
        let result = try await runResult(arguments: ["stash", "apply", reference])
        guard result.success else {
            if result.combinedText.contains("CONFLICT") {
                return .conflicts
            }
            if let error = GitShelfError.classify(applyFailure: result.combinedText) {
                throw error
            }
            throw GitClient.error(for: result)
        }
        if !keep {
            try await deleteShelf(hash: hash)
        }
        return .applied
    }

    func renameShelf(hash: String, to name: String) async throws {
        let entry = try await shelfEntry(hash: hash)
        guard let parts = entry.shelfParts else { throw GitShelfError.notFound }
        let newName = GitShelf.normalizedName(name)
        guard newName != parts.name else { return }
        let message = parts.prefix + GitShelf.marker + newName
        if entry.index == 0 {
            try await renameTopShelf(entry, to: message)
        } else {
            try await storeShelf(hash: hash, message: message)
            try await dropStaleShelf(entry)
        }
    }

    private func renameTopShelf(_ entry: GitShelfStashEntry, to message: String) async throws {
        try await dropStashEntry(at: entry.index)
        do {
            try await storeShelf(hash: entry.hash, message: message)
        } catch {
            try? await storeShelf(hash: entry.hash, message: entry.subject)
            throw error
        }
    }

    private func dropStaleShelf(_ entry: GitShelfStashEntry) async throws {
        let entries = try await shelfStashEntries()
        guard let stale = entries.first(where: { $0.hash == entry.hash && $0.subject == entry.subject }) else {
            throw GitShelfError.notFound
        }
        try await dropStashEntry(at: stale.index)
    }

    private func storeShelf(hash: String, message: String) async throws {
        _ = try await run(arguments: ["stash", "store", "--message", message, hash])
    }

    private func dropStashEntry(at index: Int) async throws {
        _ = try await run(arguments: ["stash", "drop", "stash@{\(index)}"])
    }

    func deleteShelf(hash: String) async throws {
        let reference = try await shelfReference(of: hash)
        _ = try await run(arguments: ["stash", "drop", reference])
    }

    func shelfReference(of hash: String) async throws -> String {
        let entry = try await shelfEntry(hash: hash)
        return "stash@{\(entry.index)}"
    }

    private func shelfEntry(hash: String) async throws -> GitShelfStashEntry {
        guard let entry = try await shelfStashEntries().first(where: { $0.hash == hash }) else {
            throw GitShelfError.notFound
        }
        return entry
    }

    private func topStashHash() async throws -> String? {
        let output = try await run(arguments: ["rev-parse", "-q", "--verify", "refs/stash"], accepting: [0, 1])
        let hash = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return hash.isEmpty ? nil : hash
    }
}
