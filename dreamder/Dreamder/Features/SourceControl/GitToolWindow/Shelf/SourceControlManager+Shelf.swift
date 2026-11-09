import Foundation

extension SourceControlManager {
    func shelfList() async throws -> [GitShelf] {
        try await gitClient.shelfList()
    }

    @discardableResult
    func shelveChanges(files: [GitChangedFile], name: String) async throws -> GitShelf {
        let paths = shelfPaths(for: files)
        let urls = paths.map { repositoryURL.appending(path: $0) }
        try refuseUnsavedDocuments(at: urls)
        let shelf = try await gitClient.shelve(paths: paths, name: name)
        await finishShelfChange(urls: urls)
        return shelf
    }

    func unshelve(_ shelf: GitShelf, keep: Bool) async throws -> GitShelfUnshelveOutcome {
        let urls = shelf.files.map { repositoryURL.appending(path: $0.path) }
        try refuseUnsavedDocuments(at: urls)
        let outcome: GitShelfUnshelveOutcome
        do {
            outcome = try await gitClient.unshelve(hash: shelf.hash, keep: keep)
        } catch {
            await refreshShelfState()
            throw error
        }
        await finishShelfChange(urls: urls)
        if outcome == .conflicts {
            await branchOpsRefresh()
        }
        return outcome
    }

    func renameShelf(_ shelf: GitShelf, to name: String) async throws {
        try await gitClient.renameShelf(hash: shelf.hash, to: name)
        try? await refreshStashEntries()
    }

    func deleteShelf(_ shelf: GitShelf) async throws {
        try await gitClient.deleteShelf(hash: shelf.hash)
        try? await refreshStashEntries()
    }

    private func shelfPaths(for files: [GitChangedFile]) -> [String] {
        var seen = Set<String>()
        var paths: [String] = []
        for file in files {
            let candidates = [DiffPath.relativePath(of: file.fileURL, from: repositoryURL), file.originalFilename ?? ""]
            for path in candidates where !path.isEmpty && seen.insert(path).inserted {
                paths.append(path)
            }
        }
        return paths
    }

    private func refuseUnsavedDocuments(at urls: [URL]) throws {
        let unsaved = unsavedOpenDocumentPaths(touchedBy: urls)
        guard unsaved.isEmpty else {
            throw GitShelfError.unsavedChanges(unsaved.joined(separator: "\n"))
        }
    }

    private func finishShelfChange(urls: [URL]) async {
        reloadUneditedOpenDocuments(touchedBy: urls)
        await refreshShelfState()
    }

    private func refreshShelfState() async {
        try? await refreshStashEntries()
        await refreshAllChangedFiles()
    }
}
