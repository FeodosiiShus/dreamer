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
        indexGeneration += 1
        let generation = indexGeneration
        indexingTask?.cancel()

        if let previousNotificationID = indexingNotificationID {
            NotificationCenter.default.post(
                name: .taskNotification,
                object: nil,
                userInfo: ["id": previousNotificationID, "action": "delete"]
            )
            indexingNotificationID = nil
        }

        let runIndexer = SearchIndexer.Memory.create()
        indexer = runIndexer

        guard let url = workspace?.fileURL, let runIndexer else {
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
        NotificationCenter.default.post(name: .taskNotification, object: nil, userInfo: createInfo)

        indexingTask = Task.detached { [weak self] in
            guard let self else { return }

            let filePaths = Self.fileURLs(at: url, excluding: ExcludedDirectories.rules(covering: url))
            let asyncController = SearchIndexer.AsyncManager(index: runIndexer)
            var lastProgress: Double = 0

            for await (file, index) in AsyncFileIterator(fileURLs: filePaths) {
                guard await self.isCurrentIndexRun(generation) else { return }
                _ = await asyncController.addText(files: [file], flushWhenComplete: false)
                let progress = Double(index) / Double(filePaths.count)

                // Send only if difference is > 0.5%, to keep updates from sending too frequently
                if progress - lastProgress > 0.005 || index == filePaths.count - 1 {
                    lastProgress = progress
                    guard await self.isCurrentIndexRun(generation) else { return }
                    await MainActor.run {
                        self.indexStatus = .indexing(progress: progress)
                    }
                    let updateInfo: [String: Any] = [
                        "id": uuidString,
                        "action": "update",
                        "percentage": progress
                    ]
                    NotificationCenter.default.post(name: .taskNotification, object: nil, userInfo: updateInfo)
                }
            }
            asyncController.index.flush()

            guard await self.isCurrentIndexRun(generation) else { return }

            await MainActor.run {
                self.indexStatus = .done
                self.indexingNotificationID = nil
            }
            let updateInfo: [String: Any] = [
                "id": uuidString,
                "action": "update",
                "title": "Finished indexing",
                "isLoading": false
            ]
            NotificationCenter.default.post(name: .taskNotification, object: nil, userInfo: updateInfo)

            let deleteInfo = [
                "id": uuidString,
                "action": "deleteWithDelay",
                "delay": 4.0
            ]
            NotificationCenter.default.post(name: .taskNotification, object: nil, userInfo: deleteInfo)
        }
    }

    private func isCurrentIndexRun(_ generation: Int) async -> Bool {
        await MainActor.run {
            self.indexGeneration == generation
        }
    }

    static func fileURLs(at url: URL, excluding exclusions: ExclusionRules) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }
        var urls: [URL] = []
        for case let fileURL as URL in enumerator {
            let isDirectory = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            if isDirectory {
                if exclusions.isExclusionRoot(fileURL) {
                    enumerator.skipDescendants()
                }
                continue
            }
            urls.append(fileURL)
        }
        return urls
    }

    /// Retrieves the contents of a files  from the specified file paths.
    ///
    /// - Parameter filePaths: An array of file URLs representing the paths of the files.
    ///
    /// - Returns: An array of `TextFile` objects containing the standardised file URLs and text content.
    func getFileContent(from filePaths: [URL]) async -> [SearchIndexer.AsyncManager.TextFile] {
        var textFiles = [SearchIndexer.AsyncManager.TextFile]()
        for file in filePaths {
            if let content = try? String(contentsOf: file) {
                textFiles.append(
                    SearchIndexer.AsyncManager.TextFile(url: file.standardizedFileURL, text: content)
                )
            }
        }
        return textFiles
    }
}
