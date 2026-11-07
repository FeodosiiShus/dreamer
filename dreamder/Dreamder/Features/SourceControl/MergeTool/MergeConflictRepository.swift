import Foundation

nonisolated enum MergeToolErrorText {
    static func describe(_ error: Error) -> String {
        if let gitError = error as? GitClient.GitClientError {
            return gitError.description
        }
        return error.localizedDescription
    }
}

struct MergeConflictRepository {
    enum StageContent: Equatable {
        case missing
        case binary
        case text(String)

        var isBinary: Bool { self == .binary }

        var text: String {
            if case let .text(value) = self {
                return value
            }
            return ""
        }
    }

    struct RevisionSet: Equatable {
        let base: StageContent
        let ours: StageContent
        let theirs: StageContent

        var isBinary: Bool { base.isBinary || ours.isBinary || theirs.isBinary }
    }

    let gitClient: GitClient
    let rootURL: URL

    init(gitClient: GitClient, rootURL: URL) {
        self.gitClient = gitClient
        self.rootURL = rootURL
    }

    init?(workspace: WorkspaceDocument) {
        guard let manager = workspace.sourceControlManager else { return nil }
        self.init(gitClient: manager.gitClient, rootURL: manager.repositoryURL)
    }

    func entries() async -> [MergeConflictEntry] {
        guard let output = try? await gitClient.run("status --porcelain=v2 -z") else { return [] }
        return MergeConflictStatusParser.parse(output).sorted {
            $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }
    }

    func context() async -> MergeConflictContext {
        var state = MergeRepositoryState()
        state.currentBranch = await trimmedOutput("rev-parse --abbrev-ref HEAD") ?? ""

        let gitDirectoryPath = await trimmedOutput("rev-parse --absolute-git-dir")
            ?? rootURL.appending(path: ".git").path(percentEncoded: false)
        let gitDirectory = URL(filePath: gitDirectoryPath)

        let exists: (String) -> Bool = { relative in
            FileManager.default.fileExists(
                atPath: gitDirectory.appending(path: relative).path(percentEncoded: false)
            )
        }

        if exists("MERGE_HEAD"), let head = readGitFile(gitDirectory, "MERGE_HEAD") {
            state.mergeSource = await describe(head)
        }

        state.hasRebaseInProgress = exists("rebase-merge") || exists("rebase-apply") || exists("REBASE_HEAD")
        if state.hasRebaseInProgress {
            let headName = readGitFile(gitDirectory, "rebase-merge/head-name")
                ?? readGitFile(gitDirectory, "rebase-apply/head-name")
            state.rebaseBranch = headName.map(Self.shortBranchName)
            let onto = readGitFile(gitDirectory, "rebase-merge/onto")
                ?? readGitFile(gitDirectory, "rebase-apply/onto")
            if let onto {
                state.rebaseOnto = await describe(onto)
            }
        }

        if exists("CHERRY_PICK_HEAD") {
            state.cherryPickHash = await trimmedOutput("rev-parse --short CHERRY_PICK_HEAD")
        }

        state.hasStash = exists("refs/stash")

        return MergeConflictContext.make(from: state)
    }

    func revisions(for path: String) async -> RevisionSet {
        async let base = stageText(1, path: path)
        async let ours = stageText(2, path: path)
        async let theirs = stageText(3, path: path)
        return await RevisionSet(base: base, ours: ours, theirs: theirs)
    }

    func accept(
        _ choice: MergeSideChoice,
        entry: MergeConflictEntry,
        context: MergeConflictContext
    ) async throws {
        let change = entry.change(for: choice, swapsSides: context.swapsSides)
        let quotedPath = GitClient.logGraphQuote(entry.path)
        if change.isRemoval {
            _ = try await gitClient.run("rm -f -- \(quotedPath)")
            return
        }
        let flag = useTheirsFlag(choice, swapsSides: context.swapsSides) ? "--theirs" : "--ours"
        _ = try await gitClient.run("checkout \(flag) -- \(quotedPath)")
        _ = try await gitClient.run("add -- \(quotedPath)")
    }

    func stageResult(_ text: String, path: String) async throws {
        let url = rootURL.appending(path: path)
        try text.write(to: url, atomically: true, encoding: .utf8)
        _ = try await gitClient.run("add -- \(GitClient.logGraphQuote(path))")
    }

    nonisolated static func shortBranchName(_ ref: String) -> String {
        ref.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "refs/heads/", with: "")
            .replacingOccurrences(of: "refs/tags/", with: "")
    }

    private func useTheirsFlag(_ choice: MergeSideChoice, swapsSides: Bool) -> Bool {
        let asksTheirs = choice == .theirs
        return asksTheirs != swapsSides
    }

    private func stageText(_ stage: Int, path: String) async -> StageContent {
        let object = ":\(stage):\(path)"
        guard let output = try? await gitClient.run("show \(GitClient.logGraphQuote(object))") else {
            return .missing
        }
        if output.contains("\u{0}") {
            return .binary
        }
        return .text(output)
    }

    private func describe(_ revision: String) async -> String? {
        let value = revision.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        let quoted = GitClient.logGraphQuote(value)

        if let output = await trimmedOutput(
            "for-each-ref --format=\"%(refname:short)\" --points-at=\(quoted) refs/heads/"
        ) {
            let name = output.split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { !$0.isEmpty }
            if let name {
                return name
            }
        }

        if let output = await trimmedOutput("name-rev --name-only --no-undefined \(quoted)"),
           !output.contains("~"),
           !output.contains("^"),
           output != "undefined" {
            return output.replacingOccurrences(of: "refs/remotes/", with: "")
        }

        if let output = await trimmedOutput("rev-parse --short \(quoted)") {
            return output
        }

        return nil
    }

    private func trimmedOutput(_ command: String) async -> String? {
        guard let output = try? await gitClient.run(command) else { return nil }
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func readGitFile(_ gitDirectory: URL, _ relativePath: String) -> String? {
        let url = gitDirectory.appending(path: relativePath)
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
