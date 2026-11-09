import Foundation
import Observation

@Observable
@MainActor
final class GitLogViewModel {
    static let defaultLoadLimit = GitClient.logGraphDefaultLimit

    @ObservationIgnored let loadLimit: Int

    init(loadLimit: Int = GitLogViewModel.defaultLoadLimit) {
        self.loadLimit = loadLimit
    }

    private(set) var commits: [GitLogCommit] = []
    private(set) var visibleCommits: [GitLogCommit] = []
    private(set) var graphRows: [String: GitLogGraphRow] = [:]
    private(set) var laneCount = 1
    private(set) var selectedHash: String?
    private(set) var selectedFiles: [GitChangedFile] = []
    private(set) var selectedMessage = ""
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var filters = GitLogFilterCollection()
    private(set) var options = GitLogOptions()
    private(set) var availableUsers: [GitLogUser] = []
    private(set) var currentUser: GitLogUser?

    @ObservationIgnored weak var manager: SourceControlManager?
    @ObservationIgnored private var lastQuery = GitLogFilterCollection()
    @ObservationIgnored private(set) var detailsAppliedByGit = false
    @ObservationIgnored private var baseIsTruncated = false
    @ObservationIgnored private var generation = 0

    var tabTitle: String {
        guard let branch = filters.branch, !branch.isEmpty else { return "Log" }
        return "Log: \(branch.displayText)"
    }

    var selectedCommit: GitLogCommit? {
        guard let selectedHash else { return nil }
        return commits.first { $0.hash == selectedHash }
    }

    func load(manager: SourceControlManager) async {
        self.manager = manager
        baseIsTruncated = false
        await reload(manager: manager)
    }

    func setFilters(_ newFilters: GitLogFilterCollection) async {
        let old = filters
        filters = newFilters
        if old.repositoryFilters != newFilters.repositoryFilters {
            baseIsTruncated = false
        }
        guard let manager else { return }
        await ensureCurrentUser(manager: manager)
        let desired = baseIsTruncated ? newFilters : newFilters.repositoryFilters
        if desired != lastQuery {
            await reload(manager: manager)
        } else {
            await rebuild()
            await reselect(refresh: false)
        }
    }

    func setBranchFilter(_ branch: GitLogBranchFilter?) async {
        var updated = filters
        updated.branch = branch
        selectedHash = nil
        await setFilters(updated)
    }

    func setFirstParent(_ enabled: Bool) async {
        guard options.firstParent != enabled else { return }
        options.firstParent = enabled
        baseIsTruncated = false
        guard let manager else { return }
        await reload(manager: manager)
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

    private var userResolver: GitLogUserResolver {
        GitLogUserResolver(currentUser: currentUser, allUsers: availableUsers)
    }

    private func ensureCurrentUser(manager: SourceControlManager) async {
        guard currentUser == nil, filters.user?.userNames.contains(GitLogUserFilter.me) == true else { return }
        currentUser = await manager.gitClient.logGraphCurrentUser()
    }

    private func reload(manager: SourceControlManager) async {
        isLoading = true
        defer { isLoading = false }
        generation += 1
        let token = generation
        await ensureCurrentUser(manager: manager)

        do {
            let client = manager.gitClient
            let activeFilters = filters
            let activeOptions = options
            let useFullQuery = baseIsTruncated
            var query = useFullQuery ? activeFilters : activeFilters.repositoryFilters
            var fetched = try await client.logGraph(
                filters: query,
                options: activeOptions,
                userResolver: userResolver,
                limit: loadLimit
            )
            if !useFullQuery {
                availableUsers = GitLogUserResolver.users(of: fetched)
                baseIsTruncated = fetched.count >= loadLimit
                if baseIsTruncated && activeFilters.hasDetailsFilters {
                    query = activeFilters
                    fetched = try await client.logGraph(
                        filters: query,
                        options: activeOptions,
                        userResolver: userResolver,
                        limit: loadLimit
                    )
                }
            }
            guard token == generation else { return }
            lastQuery = query
            detailsAppliedByGit = query.hasDetailsFilters
            commits = fetched
            errorMessage = nil
        } catch {
            guard token == generation else { return }
            commits = []
            visibleCommits = []
            graphRows = [:]
            laneCount = 1
            lastQuery = GitLogFilterCollection()
            detailsAppliedByGit = false
            errorMessage = (error as? GitClient.GitClientError)?.description ?? error.localizedDescription
        }

        if errorMessage == nil {
            await rebuild()
        }
        await reselect()
    }

    private func rebuild() async {
        generation += 1
        let token = generation
        let loaded = commits
        let visible = detailsAppliedByGit ? loaded : filters.applyingInMemory(to: loaded, resolver: userResolver)
        let visibleHashes: Set<String>? = visible.count == loaded.count ? nil : Set(visible.map(\.hash))
        let snapshot = await GitLogGraphLayout.snapshotAsync(
            commits: loaded,
            visibleHashes: visibleHashes,
            firstParentOnly: options.firstParent
        )
        guard token == generation else { return }
        visibleCommits = visible
        var rowsByHash: [String: GitLogGraphRow] = [:]
        for row in snapshot.rows where rowsByHash[row.hash] == nil {
            rowsByHash[row.hash] = row
        }
        graphRows = rowsByHash
        laneCount = GitLogGraphLayout.displayedLaneCount(snapshot)
    }

    private func reselect(refresh: Bool = true) async {
        if let selectedHash, visibleCommits.contains(where: { $0.hash == selectedHash }) {
            if refresh {
                await select(hash: selectedHash)
            }
        } else if let first = visibleCommits.first {
            await select(hash: first.hash)
        } else {
            await select(hash: nil)
        }
    }
}
