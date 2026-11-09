//
//  WorkspaceDocument+Index.swift
//  Dreamder
//
//  Created by Tommy Ludwig on 02.01.24.
//

import Foundation

extension WorkspaceDocument.SearchState {
    /// Adds the contents of the current workspace URL to the search index.
    /// That means that the contents of the workspace will be indexed and searchable.
    func addProjectToIndex() {
        rebuildIndex(reloadingScope: true)
    }

    private func rebuildIndex(reloadingScope: Bool) {
        indexGeneration += 1
        let generation = indexGeneration
        indexingTask?.cancel()

        if let previousNotificationID = indexingNotificationID {
            postTaskNotification(["id": previousNotificationID, "action": "delete"])
            indexingNotificationID = nil
        }

        let runIndexer = SearchIndexer.Memory.create()
        indexer = runIndexer

        guard let scope = workspace?.fileScope, let runIndexer else {
            indexStatus = .done
            return
        }

        indexStatus = .indexing(progress: 0.0)
        let uuidString = UUID().uuidString
        indexingNotificationID = uuidString
        let createInfo: [String: Any] = [
            "id": uuidString,
            "action": "create",
            "title": "Indexing | Processing files",
            "message": "Creating an index to enable fast and accurate searches within your codebase.",
            "isLoading": true
        ]
        postTaskNotification(createInfo)

        if reloadingScope {
            scope.reload()
        }
        let changes = scope.changes()
        indexingTask = Task { [weak self] in
            await Self.runIndexing(
                scope: scope,
                indexer: runIndexer,
                changes: changes,
                publishProgress: { progress in
                    self?.publishIndexProgress(progress, generation: generation, notificationID: uuidString) ?? false
                },
                finish: {
                    self?.finishIndexRun(generation: generation, notificationID: uuidString) ?? false
                },
                restart: {
                    self?.restartIndexRun(after: generation)
                }
            )
        }
    }

    nonisolated private static let progressReportingThreshold = 0.005

    @concurrent
    private static func runIndexing(
        scope: WorkspaceFileScope,
        indexer: SearchIndexer,
        changes: AsyncStream<WorkspaceFileChange>,
        publishProgress: @MainActor @Sendable (Double) -> Bool,
        finish: @MainActor @Sendable () -> Bool,
        restart: @MainActor @Sendable () -> Void
    ) async {
        let filePaths = await scope.enumerateFiles(limit: nil)
        let asyncController = SearchIndexer.AsyncManager(index: indexer)
        var lastProgress: Double = 0

        let files = AsyncFileIterator(fileURLs: filePaths, isIndexable: { scope.isIndexableText($0) })
        for await (file, index) in files {
            guard !Task.isCancelled else { return }
            _ = await asyncController.addText(files: [file], flushWhenComplete: false)
            let progress = Double(index) / Double(filePaths.count)

            if progress - lastProgress > progressReportingThreshold || index == filePaths.count - 1 {
                lastProgress = progress
                guard await publishProgress(progress) else { return }
            }
        }
        indexer.flush()

        guard await finish() else { return }

        for await change in changes {
            guard !Task.isCancelled else { return }
            switch change {
            case .reset:
                await restart()
                return
            case .delta(let updated, let removed):
                await apply(updated: updated, removed: removed, to: indexer, scope: scope)
            }
        }
    }

    private func publishIndexProgress(_ progress: Double, generation: Int, notificationID: String) -> Bool {
        let isCurrent = indexGeneration == generation
        if isCurrent {
            indexStatus = .indexing(progress: progress)
            let updateInfo: [String: Any] = [
                "id": notificationID,
                "action": "update",
                "percentage": progress
            ]
            postTaskNotification(updateInfo)
        }
        return isCurrent
    }

    private func finishIndexRun(generation: Int, notificationID: String) -> Bool {
        let isCurrent = indexGeneration == generation
        if isCurrent {
            indexStatus = .done
            indexingNotificationID = nil
            postTaskNotification(["id": notificationID, "action": "delete"])
        }
        return isCurrent
    }

    private func restartIndexRun(after generation: Int) {
        if indexGeneration == generation {
            rebuildIndex(reloadingScope: false)
        }
    }

    private func postTaskNotification(_ info: [String: Any]) {
        var scoped = info
        scoped["workspace"] = workspace?.taskNotificationHandler.workspaceURL
        notificationCenter.post(name: .taskNotification, object: nil, userInfo: scoped)
    }

    @concurrent
    static func apply(
        updated: [URL],
        removed: [URL],
        to indexer: SearchIndexer,
        scope: WorkspaceFileScope
    ) async {
        if !removed.isEmpty {
            let removedPaths = WorkspaceRemovedPaths(removed.map(\.standardizedFileURL))
            indexer.removeDocuments(urls: indexer.documents().filter { removedPaths.covers($0) })
        }
        var files: [SearchIndexer.AsyncManager.TextFile] = []
        for url in updated {
            let indexedURL = url.standardizedFileURL
            if scope.isIndexableText(url), let content = try? String(contentsOf: url, encoding: .utf8) {
                files.append(SearchIndexer.AsyncManager.TextFile(url: indexedURL, text: content))
            } else {
                _ = indexer.removeDocument(url: indexedURL)
            }
        }
        _ = await SearchIndexer.AsyncManager(index: indexer).addText(files: files, flushWhenComplete: false)
        indexer.flush()
    }
}
