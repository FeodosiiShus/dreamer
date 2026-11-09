import Foundation

@Observable
final class CommitToolWindowViewModel {
    nonisolated struct AmendPrefill: Equatable, Sendable {
        let beforeAmend: String
        let amendMessage: String
    }

    var message = ""
    var amend = false
    var excludedIDs: Set<String> = []
    var includedUnversionedIDs: Set<String> = []
    var expandedIDs: Set<String> = []
    private(set) var hunksByFile: [String: [PartialCommitHunk]] = [:]
    private(set) var excludedHunkIDs: [String: Set<String>] = [:]
    private(set) var amendPrefill: AmendPrefill?
    private(set) var isCommitting = false
    typealias HunkStager = (GitClient, String, Set<String>) async throws -> PartialStagingOutcome

    @ObservationIgnored var stageHunks: HunkStager = { client, path, excluded in
        try await client.stageSelectedHunks(path: path, excluding: excluded)
    }

    static func isUnversioned(_ file: GitChangedFile) -> Bool {
        file.status == .untracked && file.stagedStatus == GitStatus.none
    }

    static func supportsHunks(_ file: GitChangedFile) -> Bool {
        let plain: [GitStatus] = [.none, .modified]
        return plain.contains(file.status)
            && plain.contains(file.stagedStatus)
            && (file.status == .modified || file.stagedStatus == .modified)
    }

    func isIncluded(_ file: GitChangedFile) -> Bool {
        if Self.isUnversioned(file) {
            return includedUnversionedIDs.contains(file.id)
        }
        return !excludedIDs.contains(file.id)
    }

    func setIncluded(_ included: Bool, for file: GitChangedFile) {
        if Self.isUnversioned(file) {
            if included {
                includedUnversionedIDs.insert(file.id)
            } else {
                includedUnversionedIDs.remove(file.id)
            }
        } else if included {
            excludedIDs.remove(file.id)
            excludedHunkIDs[file.id] = nil
        } else {
            excludedIDs.insert(file.id)
            excludedHunkIDs[file.id] = nil
        }
    }

    func hunks(for file: GitChangedFile) -> [PartialCommitHunk] {
        hunksByFile[file.id] ?? []
    }

    func canExpand(_ file: GitChangedFile) -> Bool {
        Self.supportsHunks(file) && hunksByFile[file.id]?.isEmpty != true
    }

    func isExpanded(_ file: GitChangedFile) -> Bool {
        canExpand(file) && expandedIDs.contains(file.id)
    }

    func isHunkIncluded(_ hunk: PartialCommitHunk, in file: GitChangedFile) -> Bool {
        isIncluded(file) && !(excludedHunkIDs[file.id]?.contains(hunk.id) ?? false)
    }

    func isPartiallyIncluded(_ file: GitChangedFile) -> Bool {
        partialExclusions(of: file) != nil
    }

    private func partialExclusions(of file: GitChangedFile) -> Set<String>? {
        guard isIncluded(file), let excluded = excludedHunkIDs[file.id] else { return nil }
        return excluded
    }

    func setHunkIncluded(_ included: Bool, _ hunk: PartialCommitHunk, in file: GitChangedFile) {
        let allIDs = Set(hunks(for: file).map(\.id))
        var excluded = isIncluded(file) ? (excludedHunkIDs[file.id] ?? []) : allIDs
        if included {
            excluded.remove(hunk.id)
        } else {
            excluded.insert(hunk.id)
        }
        excludedHunkIDs[file.id] = excluded.isEmpty ? nil : excluded
        if allIDs.isSubset(of: excluded) {
            excludedIDs.insert(file.id)
        } else {
            excludedIDs.remove(file.id)
        }
    }

    @MainActor
    func toggleExpansion(of file: GitChangedFile, using manager: SourceControlManager) async {
        if expandedIDs.remove(file.id) != nil { return }
        expandedIDs.insert(file.id)
        do {
            let loaded = try await manager.gitClient.commitToolWindowHunks(path: file.fileURL.relativePath)
            store(loaded, for: file)
        } catch {
            expandedIDs.remove(file.id)
            await manager.showAlertForError(title: "Failed to load changes", error: error)
        }
    }

    @MainActor
    func refreshHunks(using manager: SourceControlManager) async {
        let supported = manager.changedFiles.filter { Self.supportsHunks($0) }
        let present = Set(supported.map(\.id))
        expandedIDs.formIntersection(present)
        hunksByFile = hunksByFile.filter { present.contains($0.key) }
        excludedHunkIDs = excludedHunkIDs.filter { present.contains($0.key) }
        for file in supported where expandedIDs.contains(file.id) || excludedHunkIDs[file.id] != nil {
            if let loaded = try? await manager.gitClient.commitToolWindowHunks(path: file.fileURL.relativePath) {
                store(loaded, for: file)
            }
        }
    }

    private func store(_ loaded: [PartialCommitHunk], for file: GitChangedFile) {
        let previous = hunksByFile[file.id] ?? []
        hunksByFile[file.id] = loaded
        guard let excluded = excludedHunkIDs[file.id] else { return }
        let excludedBefore = previous.filter { excluded.contains($0.id) }
        let carried = Set(
            loaded.filter { hunk in excludedBefore.contains { $0.sharesOldSide(with: hunk) } }.map(\.id)
        )
        excludedHunkIDs[file.id] = carried.isEmpty ? nil : carried
        let ids = Set(loaded.map(\.id))
        if !ids.isEmpty, ids.isSubset(of: carried) {
            excludedIDs.insert(file.id)
        }
    }

    func versionedFiles(in files: [GitChangedFile]) -> [GitChangedFile] {
        files.filter { !Self.isUnversioned($0) }
    }

    func unversionedFiles(in files: [GitChangedFile]) -> [GitChangedFile] {
        files.filter { Self.isUnversioned($0) }
    }

    func canCommit(in files: [GitChangedFile]) -> Bool {
        guard !isCommitting, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return amend || files.contains(where: { isIncluded($0) })
    }

    @MainActor
    func setAmend(_ enabled: Bool, using manager: SourceControlManager) async {
        guard enabled != amend else { return }
        amend = enabled
        guard enabled else {
            restoreMessageBeforeAmend()
            return
        }
        let before = message
        guard before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            let lastMessage = try await manager.gitClient.lastCommitMessage()
            guard amend, message == before, !lastMessage.isEmpty else { return }
            message = lastMessage
            amendPrefill = AmendPrefill(beforeAmend: before, amendMessage: lastMessage)
        } catch {
            await manager.showAlertForError(title: "Commit Message Not Loaded", error: error)
        }
    }

    private func restoreMessageBeforeAmend() {
        guard let prefill = amendPrefill else { return }
        amendPrefill = nil
        if message == prefill.amendMessage {
            message = prefill.beforeAmend
        }
    }

    @MainActor
    func commit(using manager: SourceControlManager, andPush: Bool) async {
        await refreshHunks(using: manager)
        let files = manager.changedFiles
        let included = files.filter { isIncluded($0) }
        let partial = partialSelections(in: included)
        let partialIDs = Set(partial.map(\.file.id))
        let whole = included.filter { !partialIDs.contains($0.id) }
        let stagedToReset = files.filter { !isIncluded($0) && $0.isStaged }
        guard canCommit(in: files) else { return }

        isCommitting = true
        let wasAmend = amend
        do {
            if !whole.isEmpty {
                try await manager.add(whole.map(\.fileURL))
            }
            if !stagedToReset.isEmpty {
                try await manager.reset(stagedToReset.map(\.fileURL))
            }
            for (file, excluded) in partial {
                let outcome = try await stageHunks(
                    manager.gitClient,
                    file.fileURL.relativePath,
                    excluded
                )
                if outcome == .wholeFile {
                    try await manager.add([file.fileURL])
                }
            }
            try await manager.gitClient.commitToolWindow(message: message, amend: wasAmend)
        } catch {
            isCommitting = false
            await manager.showAlertForError(
                title: wasAmend ? "Failed to amend commit" : "Failed to commit",
                error: error
            )
            return
        }

        message = ""
        amend = false
        amendPrefill = nil
        excludedIDs = []
        excludedHunkIDs = [:]
        includedUnversionedIDs = []
        isCommitting = false
        await manager.refreshAllChangedFiles()
        await manager.refreshNumberOfUnsyncedCommits()
        await refreshHunks(using: manager)
        if andPush {
            manager.pushSheetIsPresented = true
        }
    }

    private func partialSelections(in included: [GitChangedFile]) -> [(file: GitChangedFile, excluded: Set<String>)] {
        included.compactMap { file -> (file: GitChangedFile, excluded: Set<String>)? in
            guard Self.supportsHunks(file), let excluded = partialExclusions(of: file) else { return nil }
            return (file, excluded)
        }
    }

    @MainActor
    func rollback(_ files: [GitChangedFile], using manager: SourceControlManager) async {
        for file in files {
            do {
                let path = file.fileURL.path(percentEncoded: false)
                if Self.isUnversioned(file) || file.status == .added || file.stagedStatus == .added {
                    if !Self.isUnversioned(file) {
                        _ = try await manager.gitClient.run("reset -- \(GitClient.logGraphQuote(path))")
                    }
                    _ = try await manager.gitClient.run("clean -f -- \(GitClient.logGraphQuote(path))")
                } else {
                    _ = try await manager.gitClient.run(
                        arguments: ["restore", "--source=HEAD", "--staged", "--worktree", "--"]
                            + Self.restoredPaths(of: file, in: manager.gitClient.directoryURL)
                    )
                }
            } catch {
                await manager.showAlertForError(title: "Failed to rollback", error: error)
                break
            }
        }
        manager.reloadOpenDocuments(at: files.map(\.fileURL))
        await manager.refreshAllChangedFiles()
        await refreshHunks(using: manager)
    }

    private static func restoredPaths(of file: GitChangedFile, in repository: URL) -> [String] {
        let path = file.fileURL.path(percentEncoded: false)
        guard file.status == .renamed || file.stagedStatus == .renamed, let original = file.originalFilename else {
            return [path]
        }
        return [path, repository.appending(path: original).path(percentEncoded: false)]
    }
}
