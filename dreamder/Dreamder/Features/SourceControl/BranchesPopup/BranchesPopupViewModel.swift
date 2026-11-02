import AppKit
import Combine
import Foundation

final class BranchesPopupViewModel: ObservableObject {
    static let showRecentBranchesKey = "dreamder.branchesPopup.showRecentBranches"
    static let showTagsKey = "dreamder.branchesPopup.showTags"
    static let groupByDirectoryKey = "dreamder.branchesPopup.groupByDirectory"
    static let showActionsKey = "dreamder.branchesPopup.showActionsInSearch"
    static let favoritesKeyPrefix = "dreamder.branchesPopup.favorites."
    static let excludedFavoritesKeyPrefix = "dreamder.branchesPopup.excludedFavorites."
    static let predefinedFavorites: Set<String> = [
        "local:master",
        "local:main",
        "remote:origin/master",
        "remote:origin/main"
    ]

    let sourceControlManager: SourceControlManager
    private let workspace: WorkspaceDocument
    private let dismissPopup: () -> Void

    var dialogs = BranchesPopupDialogs.live
    var notify: (BranchesPopupNotificationRequest) -> Void = BranchesPopupNotifications.post
    var presentRefActions: ((BranchesPopupRow) -> Void)?
    var comparePresenter: ((WorkspaceDocument, String, String) -> Void)?
    var openConflicts: (() -> Void)?

    @Published var query = "" {
        didSet {
            guard query != oldValue else { return }
            rebuild()
            selectBestMatch()
        }
    }
    @Published var sections: [BranchesPopupSection] = []
    @Published var selectedID: BranchesPopupItemID?
    @Published var expandedIDs: Set<BranchesPopupItemID> = [
        .section(.recent),
        .section(.local),
        .section(.remote)
    ]
    @Published var collapsedWhileSearching: Set<BranchesPopupItemID> = []
    @Published var collapsedGroups: Set<BranchesPopupItemID> = []
    @Published var favorites: Set<String> = []
    @Published var operationState = GitBranchOperationState.none
    @Published var isFetching = false
    @Published private(set) var runningOperations = 0
    @Published var isLoading = true
    @Published var isBlockingInput = false
    @Published var showsRecentBranches: Bool {
        didSet {
            guard showsRecentBranches != oldValue else { return }
            defaults.set(showsRecentBranches, forKey: Self.showRecentBranchesKey)
            refreshTree()
        }
    }
    @Published var showsTags: Bool {
        didSet {
            guard showsTags != oldValue else { return }
            defaults.set(showsTags, forKey: Self.showTagsKey)
            refreshTree()
        }
    }
    @Published var groupsByDirectory: Bool {
        didSet {
            guard groupsByDirectory != oldValue else { return }
            defaults.set(groupsByDirectory, forKey: Self.groupByDirectoryKey)
            refreshTree()
        }
    }
    @Published var showsActionsInSearch: Bool {
        didSet {
            guard showsActionsInSearch != oldValue else { return }
            defaults.set(showsActionsInSearch, forKey: Self.showActionsKey)
            rebuild()
            selectBestMatch()
        }
    }

    private var tags: [GitTag] = []
    private var recentNames: [String] = []
    private var cancellables = Set<AnyCancellable>()
    private let defaults: UserDefaults

    init(
        sourceControlManager: SourceControlManager,
        workspace: WorkspaceDocument,
        defaults: UserDefaults = .standard,
        dismiss: @escaping () -> Void
    ) {
        self.sourceControlManager = sourceControlManager
        self.workspace = workspace
        self.defaults = defaults
        self.dismissPopup = dismiss
        if defaults.object(forKey: Self.showRecentBranchesKey) == nil {
            defaults.set(true, forKey: Self.showRecentBranchesKey)
        }
        if defaults.object(forKey: Self.showTagsKey) == nil {
            defaults.set(true, forKey: Self.showTagsKey)
        }
        if defaults.object(forKey: Self.groupByDirectoryKey) == nil {
            defaults.set(true, forKey: Self.groupByDirectoryKey)
        }
        if defaults.object(forKey: Self.showActionsKey) == nil {
            defaults.set(true, forKey: Self.showActionsKey)
        }
        self.showsRecentBranches = defaults.bool(forKey: Self.showRecentBranchesKey)
        self.showsTags = defaults.bool(forKey: Self.showTagsKey)
        self.groupsByDirectory = defaults.bool(forKey: Self.groupByDirectoryKey)
        self.showsActionsInSearch = defaults.bool(forKey: Self.showActionsKey)
        let stored = Set(defaults.stringArray(forKey: Self.favoritesKey(for: sourceControlManager)) ?? [])
        let excluded = Set(defaults.stringArray(forKey: Self.excludedFavoritesKey(for: sourceControlManager)) ?? [])
        self.favorites = stored.union(Self.predefinedFavorites).subtracting(excluded)
        let workspace = workspace
        self.comparePresenter = { workspace, branch, current in
            Task { @MainActor in
                BranchesComparePresenter.show(workspace: workspace, branch: branch, current: current)
            }
        }
        self.openConflicts = { [weak workspace] in
            guard let workspace else { return }
            Task { @MainActor in
                MergeToolPresenter.showConflicts(workspace: workspace)
            }
        }
        observe()
    }

    var rows: [BranchesPopupRow] {
        var rows: [BranchesPopupRow] = []
        let actions = visibleActions
        let ongoing = visibleOngoingActions
        if actions.isEmpty {
            for action in ongoing {
                rows.append(ongoingRow(action))
            }
            if !ongoing.isEmpty { rows.append(separatorRow("actions-end")) }
        } else {
            for action in actions {
                if action == .newBranch, !rows.isEmpty {
                    rows.append(separatorRow("action-groups"))
                }
                if action == .newBranch {
                    for ongoingAction in ongoing {
                        rows.append(ongoingRow(ongoingAction))
                    }
                }
                rows.append(actionRow(action))
            }
            rows.append(separatorRow("actions-end"))
        }
        for section in sections {
            rows.append(sectionRow(section))
            guard isExpanded(.section(section.id)) else { continue }
            appendNodes(section.nodes, depth: 1, to: &rows)
        }
        return rows
    }

    var visibleActions: [BranchesPopupActionID] {
        let queryText = trimmedQuery
        guard !queryText.isEmpty else { return BranchesPopupActionID.allCases }
        guard showsActionsInSearch else { return [] }
        return BranchesPopupActionID.allCases.filter {
            BranchesPopupMatcher.matches(query: queryText, candidate: $0.title)
        }
    }

    var visibleOngoingActions: [BranchesPopupOngoingAction] {
        guard operationState.hasOngoingOperation else { return [] }
        return BranchesPopupOngoingAction.allCases.filter { $0.isVisible(in: operationState) }
    }

    var selectedRow: BranchesPopupRow? {
        guard let selectedID else { return nil }
        return rows.first { $0.id == selectedID }
    }

    var emptyMessage: String? {
        guard rows.allSatisfy({ !$0.isSelectable }) else { return nil }
        return trimmedQuery.isEmpty ? "Branch not found" : "Nothing found"
    }

    var preferredHeight: CGFloat {
        let rowHeight = CGFloat(rows.count) * Islands.treeRowHeight
        return min(560, max(260, rowHeight + 56))
    }

    var remoteBranchRefs: [BranchesPopupRef] {
        sourceControlManager.branches
            .filter(\.isRemote)
            .compactMap { branch -> BranchesPopupRef? in
                guard let parts = BranchesPopupTreeBuilder.remoteParts(for: branch), parts.name != "HEAD" else {
                    return nil
                }
                return BranchesPopupRef(
                    kind: .remote,
                    name: parts.name,
                    shortName: "\(parts.remote)/\(parts.name)",
                    upstream: nil,
                    isCurrent: false
                )
            }
            .sorted { $0.shortName.lowercased() < $1.shortName.lowercased() }
    }

    var remoteNames: [String] {
        sourceControlManager.remotes.map(\.name).sorted()
    }

    var currentBranchName: String {
        detectedCurrentBranchName ?? "HEAD"
    }

    private var detectedCurrentBranchName: String? {
        guard let name = sourceControlManager.currentBranch?.name, !name.isEmpty else { return nil }
        return name
    }

    private var localBranchNames: Set<String> {
        Set(sourceControlManager.branches.filter(\.isLocal).map(\.name))
    }

    private var isDetachedHead: Bool {
        detectedCurrentBranchName == nil
    }

    func refActionContext(for ref: BranchesPopupRef) -> BranchesPopupRefActionContext {
        BranchesPopupRefActionContext(
            currentName: currentBranchName,
            hasRemotes: !sourceControlManager.remotes.isEmpty,
            isDetachedHead: isDetachedHead,
            trackedBranch: ref.kind == .local ? trackedRemoteRef(for: ref) : nil
        )
    }

    func reload() async {
        await sourceControlManager.refreshBranches()
        await sourceControlManager.refreshCurrentBranch()
        let operationState = await sourceControlManager.branchOpsOperationState()
        tags = await sourceControlManager.branchOpsTags()
        recentNames = await sourceControlManager.branchOpsRecentBranchNames(limit: 40)
        await MainActor.run {
            self.operationState = operationState
            isLoading = false
            rebuild()
            selectBestMatch()
        }
    }

    func fetch() {
        guard !isFetching else { return }
        isFetching = true
        Task {
            do {
                try await sourceControlManager.branchOpsFetchAll()
                try? await sourceControlManager.refreshRemotes()
                await sourceControlManager.refreshBranches()
                await sourceControlManager.refreshCurrentBranch()
                tags = await sourceControlManager.branchOpsTags()
                recentNames = await sourceControlManager.branchOpsRecentBranchNames(limit: 40)
                await MainActor.run {
                    isFetching = false
                    refreshTree()
                }
            } catch {
                await MainActor.run { isFetching = false }
                await sourceControlManager.showAlertForError(title: "Fetch failed", error: error)
            }
        }
    }

    func moveSelection(_ delta: Int) {
        let selectableRows = rows.filter(\.isSelectable)
        guard !selectableRows.isEmpty else { return }
        guard let selectedID,
              let index = selectableRows.firstIndex(where: { $0.id == selectedID }) else {
            selectedID = delta < 0 ? selectableRows.last?.id : selectableRows.first?.id
            return
        }
        let nextIndex = (index + delta + selectableRows.count) % selectableRows.count
        self.selectedID = selectableRows[nextIndex].id
    }

    func activateSelection() {
        guard let selectedRow else { return }
        activate(selectedRow)
    }

    func activate(_ row: BranchesPopupRow) {
        switch row.kind {
        case .action:
            if let action = row.action { perform(action) }
            if let ongoingAction = row.ongoingAction { performOngoing(ongoingAction) }
        case .section, .group:
            toggleExpansion(row.id)
        case .ref:
            presentRefActions?(row)
        case .separator:
            break
        }
    }

    func toggleSelectionExpansion() {
        guard let selectedRow else { return }
        toggleExpansion(selectedRow.id)
    }

    func toggleExpansion(_ id: BranchesPopupItemID) {
        switch id {
        case .group:
            if collapsedGroups.contains(id) {
                collapsedGroups.remove(id)
            } else {
                collapsedGroups.insert(id)
            }
        case .section:
            if trimmedQuery.isEmpty {
                if expandedIDs.contains(id) {
                    expandedIDs.remove(id)
                } else {
                    expandedIDs.insert(id)
                }
            } else {
                if collapsedWhileSearching.contains(id) {
                    collapsedWhileSearching.remove(id)
                } else {
                    collapsedWhileSearching.insert(id)
                }
            }
        default:
            break
        }
    }

    func isExpanded(_ id: BranchesPopupItemID) -> Bool {
        switch id {
        case .group:
            return !collapsedGroups.contains(id)
        case .section:
            if trimmedQuery.isEmpty {
                return expandedIDs.contains(id)
            }
            return !collapsedWhileSearching.contains(id)
        default:
            return false
        }
    }

    func toggleFavorite(_ ref: BranchesPopupRef) {
        let favoritesKey = Self.favoritesKey(for: sourceControlManager)
        let excludedKey = Self.excludedFavoritesKey(for: sourceControlManager)
        var stored = Set(defaults.stringArray(forKey: favoritesKey) ?? [])
        var excluded = Set(defaults.stringArray(forKey: excludedKey) ?? [])
        let isPredefined = Self.predefinedFavorites.contains(ref.id)
        if favorites.contains(ref.id) {
            favorites.remove(ref.id)
            stored.remove(ref.id)
            if isPredefined {
                excluded.insert(ref.id)
            }
        } else {
            favorites.insert(ref.id)
            excluded.remove(ref.id)
            if !isPredefined {
                stored.insert(ref.id)
            }
        }
        defaults.set(Array(stored), forKey: favoritesKey)
        defaults.set(Array(excluded), forKey: excludedKey)
        refreshTree()
    }

    func toggleSelectedFavorite() {
        guard let ref = selectedRow?.ref else { return }
        toggleFavorite(ref)
    }

    func perform(_ action: BranchesPopupActionID) {
        switch action {
        case .updateProject:
            dismiss()
            runOperation(title: "Failed to update project") {
                try await self.sourceControlManager.branchOpsUpdateProject()
            }
        case .commit:
            dismiss()
            workspace.toolWindowManager.show(.commit)
        case .push:
            dismiss()
            sourceControlManager.pushSheetIsPresented = true
            sourceControlManager.operationBranch = sourceControlManager.currentBranch
        case .newBranch:
            promptNewBranch(from: nil)
        case .newWorktree:
            promptNewWorktree(from: nil)
        case .checkoutRevision:
            promptCheckoutRevision()
        }
    }

    func performOngoing(_ action: BranchesPopupOngoingAction) {
        runOperation(title: "\(action.title) failed") {
            switch action {
            case .rebaseAbort: try await self.sourceControlManager.branchOpsRebaseAbort()
            case .mergeAbort: try await self.sourceControlManager.branchOpsMergeAbort()
            case .cherryPickAbort: try await self.sourceControlManager.branchOpsCherryPickAbort()
            case .cherryPickContinue: try await self.sourceControlManager.branchOpsCherryPickContinue()
            case .revertAbort: break
            case .rebaseContinue: try await self.sourceControlManager.branchOpsRebaseContinue()
            case .rebaseSkip: try await self.sourceControlManager.branchOpsRebaseSkip()
            }
        }
    }

    func checkout(_ ref: BranchesPopupRef) {
        switch ref.kind {
        case .remote:
            checkoutRemote(ref)
        case .local, .tag:
            dismiss()
            runOperation(title: "Failed to check out '\(ref.shortName)'") {
                if ref.kind == .local {
                    try await self.sourceControlManager.branchOpsCheckoutLocal(ref.shortName)
                } else {
                    try await self.sourceControlManager.branchOpsCheckoutRevision(ref.shortName)
                }
            }
        }
    }

    func checkoutRemote(_ ref: BranchesPopupRef) {
        guard let parts = ref.remoteAndBranch else { return }
        let localName = parts.branch
        let existing = sourceControlManager.branches.first { $0.isLocal && $0.name == localName }
        dismiss()
        track {
            do {
                var targetName = localName
                var overwrite = false
                if let existing, existing.upstream != ref.shortName {
                    guard let name = self.dialogs.checkoutRemoteName(ref.shortName, localName) else { return }
                    guard BranchesPopupBranchName.isValid(name) else {
                        self.dialogs.error("Invalid Branch Name", "Branch name '\(name)' is not valid")
                        return
                    }
                    targetName = name
                    overwrite = await self.sourceControlManager.branchOpsBranchExists(name)
                }

                if let existing, targetName == localName, existing.upstream == ref.shortName {
                    let extraCommits = (try? await self.sourceControlManager.branchOpsCommitCount(
                        branch: localName,
                        notIn: ref.shortName
                    )) ?? 0
                    if extraCommits > 0 {
                        switch self.dialogs.checkoutRemoteLocalCommits(localName, ref.shortName, extraCommits) {
                        case .cancel:
                            return
                        case .rebase:
                            try await self.sourceControlManager.branchOpsCheckoutLocal(localName)
                            let conflicted = try await self.sourceControlManager.branchOpsRebase(onto: ref.shortName)
                            if conflicted {
                                self.notifyRebaseConflict(source: ref.shortName)
                            }
                        case .drop:
                            try await self.sourceControlManager.branchOpsResetLocalBranchToRemote(
                                localName: localName,
                                remote: ref.shortName
                            )
                        }
                    } else {
                        try await self.sourceControlManager.branchOpsCheckoutLocal(localName)
                    }
                } else {
                    try await self.sourceControlManager.branchOpsCheckoutRemoteTrackingBranch(
                        localName: targetName,
                        remote: ref.shortName,
                        overwrite: overwrite
                    )
                }
                await self.refreshAfterOperation()
            } catch {
                await self.sourceControlManager.showAlertForError(
                    title: "Failed to check out '\(ref.shortName)'",
                    error: error
                )
            }
        }
    }

    func showWorkingTreeDiff(_ ref: BranchesPopupRef) {
        let workspace = self.workspace
        let target = ref.shortName
        dismiss()
        Task { @MainActor in
            DiffViewerPresenter.showWorkingTreeDiff(workspace: workspace, against: target)
        }
    }

    func compareWithCurrent(_ ref: BranchesPopupRef) {
        let branch = ref.displayName
        let current = currentBranchName
        guard branch != current else { return }
        dismiss()
        comparePresenter?(workspace, branch, current)
    }

    func promptNewBranch(from ref: BranchesPopupRef?) {
        let startPoint = ref?.displayName
        let message = startPoint.map { "Create a new branch from '\($0)'" } ?? "Create a new branch"
        let request = BranchesPopupBranchDialogRequest(
            title: "New Branch",
            message: message,
            initialName: detectedCurrentBranchName ?? "",
            existingNames: localBranchNames,
            showsCheckout: true,
            showsUnsetUpstream: false,
            confirmTitle: "Create"
        )
        guard let result = showBranchDialog(request) else { return }
        let name = result.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard validateBranchName(name, existing: localBranchNames, overwrite: result.overwrite) else { return }
        dismiss()
        runOperation(title: "Failed to create branch '\(name)'") {
            try await self.sourceControlManager.branchOpsCreateBranch(
                name: name,
                from: startPoint,
                checkout: result.checkout,
                overwrite: result.overwrite
            )
        }
    }

    func promptNewWorktree(from ref: BranchesPopupRef?) {
        let suffix = ref.map { "-" + $0.displayName.replacingOccurrences(of: "/", with: "-") } ?? "-worktree"
        let repository = sourceControlManager.repositoryURL
        let suggested = repository
            .deletingLastPathComponent()
            .appending(path: repository.lastPathComponent + suffix)
            .path(percentEncoded: false)
        guard let path = showWorktreePathDialog(suggested), !path.isEmpty else { return }
        let startPoint = ref?.displayName
        dismiss()
        runOperation(title: "Failed to create worktree") {
            try await self.sourceControlManager.branchOpsAddWorktree(path: path, ref: startPoint)
        }
    }

    func promptCheckoutRevision() {
        let name = showNamePrompt(
            title: "Checkout Tag or Revision",
            message: "Check out a tag or any revision as a detached HEAD.",
            placeholder: "Tag or revision",
            initialValue: ""
        )
        guard let revision = name else { return }
        dismiss()
        runOperation(title: "Failed to check out '\(revision)'") {
            try await self.sourceControlManager.branchOpsCheckoutRevision(revision)
        }
    }

    func promptRename(_ ref: BranchesPopupRef) {
        var existing = localBranchNames
        existing.remove(ref.name)
        let request = BranchesPopupBranchDialogRequest(
            title: "Rename Branch \(ref.name)",
            message: "Rename '\(ref.name)' to:",
            initialName: ref.name,
            existingNames: existing,
            showsCheckout: false,
            showsUnsetUpstream: ref.upstream != nil,
            confirmTitle: "Rename"
        )
        guard let result = showBranchDialog(request) else { return }
        let name = result.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name != ref.name else { return }
        guard validateBranchName(name, existing: existing, overwrite: false) else { return }
        runOperation(title: "Failed to rename branch '\(ref.name)'") {
            try await self.sourceControlManager.branchOpsRenameBranch(
                oldName: ref.name,
                newName: name,
                unsetUpstream: result.unsetUpstream
            )
        }
    }

    func delete(_ ref: BranchesPopupRef) {
        switch ref.kind {
        case .local:
            deleteLocalBranch(ref)
        case .remote:
            deleteRemoteBranch(ref)
        case .tag:
            deleteTag(ref)
        }
    }

    func update(_ ref: BranchesPopupRef) {
        guard let upstream = ref.upstream else { return }
        runOperation(title: "Failed to update '\(ref.name)'") {
            try await self.sourceControlManager.branchOpsUpdateBranch(
                name: ref.name,
                upstream: upstream,
                isCurrent: ref.isCurrent
            )
        }
    }

    func checkoutAndUpdate(_ ref: BranchesPopupRef) {
        guard let upstream = ref.upstream else { return }
        dismiss()
        runOperation(title: "Failed to check out '\(ref.name)'") {
            try await self.sourceControlManager.branchOpsCheckoutLocal(ref.name)
            try await self.sourceControlManager.branchOpsUpdateBranch(
                name: ref.name,
                upstream: upstream,
                isCurrent: true
            )
        }
    }

    func merge(_ ref: BranchesPopupRef) {
        let source = ref.displayName
        track {
            do {
                let conflicted = try await self.sourceControlManager.branchOpsMerge(source)
                await self.refreshAfterOperation()
                if conflicted {
                    self.notifyMergeConflict(source: source)
                }
            } catch {
                await self.sourceControlManager.showAlertForError(
                    title: "Failed to merge '\(source)'",
                    error: error
                )
            }
        }
    }

    func rebaseCurrent(onto ref: BranchesPopupRef) {
        let source = ref.displayName
        track {
            do {
                let conflicted = try await self.sourceControlManager.branchOpsRebase(onto: source)
                await self.refreshAfterOperation()
                if conflicted {
                    self.notifyRebaseConflict(source: source)
                }
            } catch {
                await self.sourceControlManager.showAlertForError(
                    title: "Failed to rebase onto '\(source)'",
                    error: error
                )
            }
        }
    }

    func checkoutAndRebase(_ ref: BranchesPopupRef) {
        let currentName = currentBranchName
        let source = ref.displayName
        dismiss()
        track {
            do {
                let conflicted = try await self.sourceControlManager.branchOpsCheckoutAndRebase(
                    ref.shortName,
                    onto: currentName
                )
                await self.refreshAfterOperation()
                if conflicted {
                    self.notifyRebaseConflict(source: currentName)
                }
            } catch {
                await self.sourceControlManager.showAlertForError(
                    title: "Failed to check out '\(source)'",
                    error: error
                )
            }
        }
    }

    func pull(_ ref: BranchesPopupRef, rebase: Bool) {
        guard ref.kind == .remote else { return }
        dismiss()
        runOperation(title: "Failed to pull '\(ref.shortName)'") {
            try await self.sourceControlManager.branchOpsPull(ref: ref.shortName, rebase: rebase)
        }
    }

    func pushTag(_ ref: BranchesPopupRef, remote: String) {
        guard ref.kind == .tag else { return }
        dismiss()
        runOperation(title: "Failed to push tag '\(ref.name)'") {
            try await self.sourceControlManager.branchOpsPushTag(name: ref.name, remote: remote)
        }
    }

    func setUpstream(_ ref: BranchesPopupRef, to upstream: String?) {
        runOperation(title: "Failed to change the tracked branch") {
            try await self.sourceControlManager.branchOpsSetUpstream(branch: ref.name, upstream: upstream)
        }
    }

    func push(_ ref: BranchesPopupRef) {
        let branch: GitBranch?
        switch ref.kind {
        case .local:
            branch = sourceControlManager.branches.first { $0.isLocal && $0.name == ref.name }
        case .remote:
            branch = sourceControlManager.branches.first { $0.isRemote && $0.name == ref.shortName }
        case .tag:
            branch = nil
        }
        dismiss()
        sourceControlManager.pushSheetIsPresented = true
        if let branch {
            sourceControlManager.operationBranch = branch
        }
    }

    func dismiss() {
        dismissPopup()
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespaces)
    }

    private var treeInput: BranchesPopupTreeInput {
        BranchesPopupTreeInput(
            localBranches: sourceControlManager.branches.filter(\.isLocal),
            remoteBranches: sourceControlManager.branches.filter(\.isRemote),
            tags: tags,
            recentNames: recentNames,
            currentBranchName: detectedCurrentBranchName,
            showsRecentBranches: showsRecentBranches,
            showsTags: showsTags,
            query: query,
            favorites: favorites,
            groupsByDirectory: groupsByDirectory
        )
    }

    private static func favoritesKey(for manager: SourceControlManager) -> String {
        favoritesKeyPrefix + manager.repositoryURL.path(percentEncoded: false)
    }

    private static func excludedFavoritesKey(for manager: SourceControlManager) -> String {
        excludedFavoritesKeyPrefix + manager.repositoryURL.path(percentEncoded: false)
    }

    private func trackedRemoteRef(for ref: BranchesPopupRef) -> BranchesPopupRef? {
        guard let upstream = ref.upstream else { return nil }
        return remoteBranchRefs.first { $0.shortName == upstream }
    }

    private func observe() {
        sourceControlManager.$branches
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshTree() }
            .store(in: &cancellables)

        sourceControlManager.$currentBranch
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshTree() }
            .store(in: &cancellables)
    }

    private func rebuild() {
        let sections = BranchesPopupTreeBuilder.build(treeInput)
        if sections != self.sections {
            self.sections = sections
        }
    }

    private func refreshTree() {
        rebuild()
        if let selectedID, rows.contains(where: { $0.id == selectedID }) { return }
        selectBestMatch()
    }

    private func selectBestMatch() {
        selectedID = bestRow()?.id
    }

    private func bestRow() -> BranchesPopupRow? {
        let leaves = rows.filter(\.isSelectable)
        guard !leaves.isEmpty else { return nil }
        guard !trimmedQuery.isEmpty else {
            return leaves.first(where: { $0.ref?.isCurrent == true })
                ?? leaves.first(where: { $0.kind == .action })
                ?? leaves.first
        }
        var best: (row: BranchesPopupRow, score: Int, priority: Int)?
        for row in leaves {
            let candidate = row.ref?.shortName ?? row.title
            guard let score = BranchesPopupMatcher.score(query: trimmedQuery, candidate: candidate) else { continue }
            let priority = sectionPriority(row)
            if let currentBest = best {
                if currentBest.score < score { continue }
                if currentBest.score == score, currentBest.priority <= priority { continue }
            }
            best = (row, score, priority)
        }
        return best?.row ?? leaves.first
    }

    private func sectionPriority(_ row: BranchesPopupRow) -> Int {
        guard let ref = row.ref else { return 10 }
        switch ref.kind {
        case .local:
            return sectionID(for: row) == .recent ? 0 : 1
        case .remote:
            return 2
        case .tag:
            return 3
        }
    }

    private func sectionID(for row: BranchesPopupRow) -> BranchesPopupSectionID? {
        if case .ref(let section, _) = row.id { return section }
        return nil
    }

    private func appendNodes(_ nodes: [BranchesPopupNode], depth: Int, to rows: inout [BranchesPopupRow]) {
        for node in nodes {
            if node.kind == .group {
                rows.append(groupRow(node, depth: depth))
                guard isExpanded(node.id) else { continue }
                appendNodes(node.children, depth: depth + 1, to: &rows)
            } else {
                rows.append(refRow(node, depth: depth))
            }
        }
    }

    private func showBranchDialog(_ request: BranchesPopupBranchDialogRequest) -> BranchesPopupBranchDialogResult? {
        isBlockingInput = true
        defer { isBlockingInput = false }
        return dialogs.branchDialog(request)
    }

    private func showNamePrompt(
        title: String,
        message: String,
        placeholder: String,
        initialValue: String
    ) -> String? {
        isBlockingInput = true
        defer { isBlockingInput = false }
        return BranchesPopupPrompt.name(
            title: title,
            message: message,
            placeholder: placeholder,
            initialValue: initialValue
        )
    }

    private func showWorktreePathDialog(_ suggested: String) -> String? {
        isBlockingInput = true
        defer { isBlockingInput = false }
        return dialogs.worktreePath(suggested)
    }

    private func validateBranchName(_ name: String, existing: Set<String>, overwrite: Bool) -> Bool {
        let validation = BranchesPopupBranchName.validate(name, existingNames: existing)
        if validation == .exists, overwrite {
            return true
        }
        guard validation == .valid else {
            dialogs.error(
                "Invalid Branch Name",
                BranchesPopupBranchName.errorMessage(for: validation, name: name) ?? "Branch name is not valid"
            )
            return false
        }
        return true
    }

    private func deleteLocalBranch(_ ref: BranchesPopupRef) {
        track {
            do {
                let tip = try await self.sourceControlManager.branchOpsRevision(ref.name)
                do {
                    try await self.sourceControlManager.branchOpsDeleteLocalBranch(ref.name)
                } catch GitClient.GitClientError.branchNotFullyMerged {
                    let base = self.detectedCurrentBranchName ?? "HEAD"
                    let commits = (try? await self.sourceControlManager.branchOpsUnmergedCommits(
                        branch: ref.name,
                        base: base
                    )) ?? []
                    self.isBlockingInput = true
                    let decision = self.dialogs.unmergedDelete(ref.name, commits)
                    self.isBlockingInput = false
                    guard decision == .force else { return }
                    try await self.sourceControlManager.branchOpsDeleteLocalBranch(ref.name, force: true)
                }
                await self.refreshAfterOperation()
                self.notify(
                    BranchesPopupNotificationRequest(
                        title: "Deleted Branch: \(ref.name)",
                        description: "Branch '\(ref.name)' was deleted.",
                        actionTitle: "Restore",
                        action: { [weak self] in self?.restoreBranch(name: ref.name, tip: tip) }
                    )
                )
            } catch {
                await self.sourceControlManager.showAlertForError(
                    title: "Failed to delete branch '\(ref.name)'",
                    error: error
                )
            }
        }
    }

    private func deleteRemoteBranch(_ ref: BranchesPopupRef) {
        guard let parts = ref.remoteAndBranch else { return }
        let trackingBranches = sourceControlManager.branches.filter {
            $0.isLocal && $0.upstream == ref.shortName
        }
        isBlockingInput = true
        var message = "Delete '\(ref.shortName)' from remote '\(parts.remote)'?"
        if !trackingBranches.isEmpty {
            message += "\n\nLocal tracking branches: \(trackingBranches.map(\.name).joined(separator: ", "))"
        }
        let confirmed = dialogs.confirm("Delete Remote Branch", message, "Delete")
        var alsoDeleteTracking = false
        if confirmed, !trackingBranches.isEmpty {
            alsoDeleteTracking = dialogs.confirm(
                "Delete Tracking Branches",
                "Also delete local branches tracking '\(ref.shortName)'?",
                "Delete Local Branches"
            )
        }
        isBlockingInput = false
        guard confirmed else { return }
        let names = trackingBranches.map(\.name)
        track {
            do {
                try await self.sourceControlManager.branchOpsDeleteRemoteBranch(
                    remote: parts.remote,
                    branch: parts.branch
                )
                if alsoDeleteTracking {
                    for name in names {
                        try await self.sourceControlManager.branchOpsDeleteLocalBranch(name, force: true)
                    }
                }
                await self.refreshAfterOperation()
            } catch {
                await self.sourceControlManager.showAlertForError(
                    title: "Failed to delete remote branch '\(ref.shortName)'",
                    error: error
                )
            }
        }
    }

    private func deleteTag(_ ref: BranchesPopupRef) {
        track {
            do {
                let tip = try await self.sourceControlManager.branchOpsRevision(ref.name)
                try await self.sourceControlManager.branchOpsDeleteTag(ref.name)
                await self.refreshAfterOperation()
                self.notify(
                    BranchesPopupNotificationRequest(
                        title: "Deleted Tag: \(ref.name)",
                        description: "Tag '\(ref.name)' was deleted.",
                        actionTitle: "Restore",
                        action: { [weak self] in self?.restoreTag(name: ref.name, tip: tip) }
                    )
                )
            } catch {
                await self.sourceControlManager.showAlertForError(
                    title: "Failed to delete tag '\(ref.name)'",
                    error: error
                )
            }
        }
    }

    private func restoreBranch(name: String, tip: String) {
        track {
            do {
                try await self.sourceControlManager.branchOpsRestoreBranch(name: name, at: tip)
                await self.refreshAfterOperation()
            } catch {
                await self.sourceControlManager.showAlertForError(
                    title: "Failed to restore branch '\(name)'",
                    error: error
                )
            }
        }
    }

    private func restoreTag(name: String, tip: String) {
        track {
            do {
                try await self.sourceControlManager.branchOpsRestoreTag(name: name, at: tip)
                await self.refreshAfterOperation()
            } catch {
                await self.sourceControlManager.showAlertForError(
                    title: "Failed to restore tag '\(name)'",
                    error: error
                )
            }
        }
    }

    private func notifyMergeConflict(source: String) {
        notify(
            BranchesPopupNotificationRequest(
                title: "Branch '\(source)' merged with conflicts",
                description: "Resolve the conflicts to complete the merge.",
                actionTitle: "Resolve Conflicts…",
                action: { [weak self] in self?.openConflicts?() }
            )
        )
    }

    private func notifyRebaseConflict(source: String) {
        notify(
            BranchesPopupNotificationRequest(
                title: "Rebase stopped with conflicts",
                description: "Rebase onto '\(source)' stopped with conflicts. Resolve them or abort the rebase.",
                actionTitle: "Resolve Conflicts…",
                action: { [weak self] in self?.openConflicts?() }
            )
        )
    }

    private func track(_ body: @escaping @MainActor () async -> Void) {
        runningOperations += 1
        Task { @MainActor in
            await body()
            self.runningOperations -= 1
        }
    }

    private func runOperation(
        title: String,
        operation: @escaping () async throws -> Void
    ) {
        track {
            do {
                try await operation()
                await self.refreshAfterOperation()
            } catch {
                await self.sourceControlManager.branchOpsRefresh()
                await self.sourceControlManager.showAlertForError(title: title, error: error)
                await MainActor.run { self.refreshTree() }
            }
        }
    }

    private func refreshAfterOperation() async {
        await sourceControlManager.branchOpsRefresh()
        await refreshMetadata()
        let state = await sourceControlManager.branchOpsOperationState()
        await MainActor.run {
            operationState = state
            refreshTree()
        }
    }

    private func refreshMetadata() async {
        tags = await sourceControlManager.branchOpsTags()
        recentNames = await sourceControlManager.branchOpsRecentBranchNames(limit: 40)
    }

    private func separatorRow(_ id: String) -> BranchesPopupRow {
        BranchesPopupRow(
            id: .separator(id),
            kind: .separator,
            title: "",
            iconName: nil,
            shortcut: nil,
            detail: nil,
            counters: nil,
            matchRanges: [],
            depth: 0,
            isExpanded: false,
            ref: nil,
            action: nil,
            ongoingAction: nil,
            isFavorite: false
        )
    }

    private func actionRow(_ action: BranchesPopupActionID) -> BranchesPopupRow {
        BranchesPopupRow(
            id: .action(action),
            kind: .action,
            title: action.title,
            iconName: action.iconName,
            shortcut: action.shortcut,
            detail: nil,
            counters: nil,
            matchRanges: matchRanges(for: action.title),
            depth: 0,
            isExpanded: false,
            ref: nil,
            action: action,
            ongoingAction: nil,
            isFavorite: false
        )
    }

    private func ongoingRow(_ action: BranchesPopupOngoingAction) -> BranchesPopupRow {
        BranchesPopupRow(
            id: .ongoing(action),
            kind: .action,
            title: action.title,
            iconName: nil,
            shortcut: nil,
            detail: nil,
            counters: nil,
            matchRanges: matchRanges(for: action.title),
            depth: 0,
            isExpanded: false,
            ref: nil,
            action: nil,
            ongoingAction: action,
            isFavorite: false
        )
    }

    private func sectionRow(_ section: BranchesPopupSection) -> BranchesPopupRow {
        BranchesPopupRow(
            id: .section(section.id),
            kind: .section,
            title: section.title,
            iconName: nil,
            shortcut: nil,
            detail: nil,
            counters: nil,
            matchRanges: [],
            depth: 0,
            isExpanded: isExpanded(.section(section.id)),
            ref: nil,
            action: nil,
            ongoingAction: nil,
            isFavorite: false
        )
    }

    private func groupRow(_ node: BranchesPopupNode, depth: Int) -> BranchesPopupRow {
        BranchesPopupRow(
            id: node.id,
            kind: .group,
            title: node.title,
            iconName: "nodes/folder",
            shortcut: nil,
            detail: nil,
            counters: nil,
            matchRanges: [],
            depth: depth,
            isExpanded: isExpanded(node.id),
            ref: nil,
            action: nil,
            ongoingAction: nil,
            isFavorite: false
        )
    }

    private func refRow(_ node: BranchesPopupNode, depth: Int) -> BranchesPopupRow {
        let isFavorite = node.ref.map { favorites.contains($0.id) } ?? false
        return BranchesPopupRow(
            id: node.id,
            kind: .ref,
            title: node.title,
            iconName: iconName(for: node.ref, isFavorite: isFavorite),
            shortcut: nil,
            detail: node.detail,
            counters: node.ref?.counterText,
            matchRanges: matchRanges(for: node.title),
            depth: depth,
            isExpanded: false,
            ref: node.ref,
            action: nil,
            ongoingAction: nil,
            isFavorite: isFavorite
        )
    }

    private func iconName(for ref: BranchesPopupRef?, isFavorite: Bool) -> String? {
        guard let ref else { return nil }
        if ref.isCurrent {
            return isFavorite ? "vcs/currentBranchFavoriteLabel" : "vcs/currentBranchLabel"
        }
        if isFavorite { return "nodes/star" }
        return ref.iconName
    }

    private func matchRanges(for title: String) -> [Range<Int>] {
        guard !trimmedQuery.isEmpty else { return [] }
        return BranchesPopupMatcher.ranges(query: trimmedQuery, candidate: title) ?? []
    }
}
