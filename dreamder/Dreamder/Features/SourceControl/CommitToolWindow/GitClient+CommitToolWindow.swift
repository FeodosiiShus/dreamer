import Foundation

nonisolated enum PartialStagingOutcome: Sendable, Equatable {
    case wholeFile
    case staged
    case nothingSelected
}

nonisolated struct CommitFileHunkSource: Sendable {
    let head: Data
    let worktree: Data
    let hunks: [PartialCommitHunk]
}

nonisolated extension GitClient {
    func commitToolWindow(message: String, amend: Bool) async throws {
        var arguments = ["commit"]
        if amend {
            arguments.append("--amend")
        }
        arguments.append(contentsOf: ["--message", message])
        _ = try await run(arguments: arguments)
    }

    @concurrent
    func lastCommitMessage() async throws -> String {
        let output = try await run(arguments: ["log", "--max-count=1", "--encoding=UTF-8", "--format=%B"])
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @concurrent
    func commitToolWindowHunks(path: String) async throws -> [PartialCommitHunk] {
        try await commitToolWindowHunkSource(path: path).hunks
    }

    @concurrent
    func stageSelectedHunks(path: String, excluding excluded: Set<String>) async throws -> PartialStagingOutcome {
        let source = try await commitToolWindowHunkSource(path: path)
        guard source.hunks.contains(where: { excluded.contains($0.id) }) else { return .wholeFile }
        _ = try await run(arguments: ["reset", "-q", "--", path])
        let selected = Set(source.hunks.map(\.id)).subtracting(excluded)
        guard let patch = PartialCommitPatchBuilder.patch(
            path: path,
            head: source.head,
            worktree: source.worktree,
            hunks: source.hunks,
            selected: selected
        ) else {
            return .nothingSelected
        }
        let patchURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "dreamder-partial-\(UUID().uuidString).patch")
        try patch.write(to: patchURL)
        defer { try? FileManager.default.removeItem(at: patchURL) }
        _ = try await run(arguments: [
            "apply", "--cached", "--recount", "--whitespace=nowarn", patchURL.path(percentEncoded: false)
        ])
        return .staged
    }

    @concurrent
    private func commitToolWindowHunkSource(path: String) async throws -> CommitFileHunkSource {
        let diff = try await run(arguments: [
            "diff", "HEAD", "-U0", "--no-color", "--no-ext-diff", "--no-textconv", "--no-renames", "--", path
        ])
        let headers = PartialCommitDiffParser.hunks(inDiff: diff)
        guard !headers.isEmpty else {
            return CommitFileHunkSource(head: Data(), worktree: Data(), hunks: [])
        }
        let head = try await runData("cat-file blob \(Self.logGraphQuote("HEAD:" + path))")
        let worktree = try Data(contentsOf: directoryURL.appending(path: path))
        return CommitFileHunkSource(
            head: head,
            worktree: worktree,
            hunks: PartialCommitPatchBuilder.hunks(from: headers, head: head, worktree: worktree)
        )
    }
}
