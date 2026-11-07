import Foundation
import Observation

@Observable
@MainActor
final class GitLogViewModel {
    private(set) var commits: [GitLogCommit] = []
    private(set) var graphRows: [String: GitLogGraphRow] = [:]
    private(set) var laneCount = 1
    private(set) var selectedHash: String?
    private(set) var selectedFiles: [GitChangedFile] = []
    private(set) var selectedMessage = ""
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    var searchText = ""
    private(set) var branchFilter = GitLogBranchFilter.all

    @ObservationIgnored weak var manager: SourceControlManager?

    var tabTitle: String {
        branchFilter.ref == nil ? "Log" : "Log: \(branchFilter.title)"
    }

    var selectedCommit: GitLogCommit? {
        guard let selectedHash else { return nil }
        return commits.first { $0.hash == selectedHash }
    }

    var visibleCommits: [GitLogCommit] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return commits }
        return commits.filter { $0.matches(graphText: query) }
    }

    func load(manager: SourceControlManager) async {
        self.manager = manager
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await manager.gitClient.logGraph(ref: branchFilter.ref)
            let rows = GitLogGraphLayout.rows(for: fetched)
            commits = fetched
            graphRows = Dictionary(rows.map { ($0.hash, $0) }, uniquingKeysWith: { first, _ in first })
            laneCount = GitLogGraphLayout.laneCount(rows)
            errorMessage = nil
        } catch {
            commits = []
            graphRows = [:]
            laneCount = 1
            errorMessage = (error as? GitClient.GitClientError)?.description ?? error.localizedDescription
        }

        if let selectedHash, commits.contains(where: { $0.hash == selectedHash }) {
            await select(hash: selectedHash)
        } else if let first = commits.first {
            await select(hash: first.hash)
        } else {
            await select(hash: nil)
        }
    }

    func setBranchFilter(_ filter: GitLogBranchFilter) async {
        branchFilter = filter
        selectedHash = nil
        guard let manager else { return }
        await load(manager: manager)
    }

    func select(hash: String?) async {
        selectedHash = hash
        guard let hash, let manager, let commit = commits.first(where: { $0.hash == hash }) else {
            selectedFiles = []
            selectedMessage = ""
            return
        }
        selectedMessage = commit.subject
        selectedFiles = []
        var files = (try? await manager.gitClient.logGraphChangedFiles(commit: commit)) ?? []
        if files.isEmpty {
            files = await manager.getCommitChangedFiles(commitSHA: hash)
        }
        let message = (try? await manager.gitClient.logGraphMessage(hash: hash)) ?? ""
        guard selectedHash == hash else { return }
        selectedFiles = files
        if !message.isEmpty {
            selectedMessage = message
        }
    }
}
