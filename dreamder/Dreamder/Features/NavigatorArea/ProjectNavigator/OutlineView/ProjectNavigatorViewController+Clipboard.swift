import AppKit

extension ProjectNavigatorViewController {
    nonisolated struct PasteEntry: Sendable {
        let source: URL
        let destination: URL
        let isCut: Bool
        let replacesExisting: Bool
    }

    struct PastePlan {
        var entries: [PasteEntry] = []
        var rejected: [String] = []
    }

    var selectedFiles: [CEWorkspaceFile] {
        outlineView.selectedRowIndexes.compactMap { outlineView.item(atRow: $0) as? CEWorkspaceFile }
    }

    var canPaste: Bool {
        clipboard.hasFiles || clipboard.text != nil
    }

    func copyToClipboard(_ items: [CEWorkspaceFile]) {
        guard !items.isEmpty else { return }
        clipboard.write(items.map(\.url), isCut: false)
    }

    func cutToClipboard(_ items: [CEWorkspaceFile]) {
        let movable = items.filter { !$0.isRoot }
        guard !movable.isEmpty else { return }
        clipboard.write(movable.map(\.url), isCut: true)
    }

    @discardableResult
    func pasteFromClipboard(into item: CEWorkspaceFile?) -> Bool {
        guard let anchor = item ?? content.first, let folder = containingFolder(of: anchor) else { return false }
        if clipboard.hasFiles {
            pasteTask = Task { await paste(into: folder) }
            return true
        }
        guard let text = clipboard.text else { return false }
        beginCreation(kind: .file, in: folder, contents: Data(text.utf8))
        return true
    }

    func paste(into folder: CEWorkspaceFile) async {
        guard let manager = workspace?.workspaceFileManager else { return }
        let isCut = clipboard.isCut
        let plan = pastePlan(into: folder, isCut: isCut, fileManager: manager.fileManager)
        let outcomes = await Self.transfer(plan.entries, using: fileOperations)
        var pasted: [URL] = []
        var firstError: Error?
        var staleDirectories: [URL] = [folder.url]
        for (entry, outcome) in zip(plan.entries, outcomes) {
            switch outcome {
            case .success:
                pasted.append(entry.destination)
                if entry.isCut {
                    retargetTabs(from: entry.source, to: entry.destination)
                    staleDirectories.append(entry.source.deletingLastPathComponent())
                }
            case .failure(let error):
                firstError = firstError ?? error
            }
        }
        if let refreshError = refresh(directories: staleDirectories, in: manager) {
            firstError = firstError ?? refreshError
        }
        if isCut, !pasted.isEmpty {
            clipboard.clear()
        }

        expandParent(item: folder)
        outlineView.reloadItem(folder, reloadChildren: true)
        let rows = pasted.compactMap { manager.getFile($0.path(percentEncoded: false), createIfNotFound: true) }
            .map { outlineView.row(forItem: $0) }
            .filter { $0 >= 0 }
        shouldSendSelectionUpdate = false
        outlineView.selectRowIndexes(IndexSet(rows), byExtendingSelection: false)
        shouldSendSelectionUpdate = true
        reportPasteProblems(rejected: plan.rejected, error: firstError)
    }

    func pastePlan(into folder: CEWorkspaceFile, isCut: Bool, fileManager: FileManager) -> PastePlan {
        var plan = PastePlan()
        for source in clipboard.fileURLs {
            var isDirectoryFlag: ObjCBool = false
            let sourcePath = source.path(percentEncoded: false)
            guard fileManager.fileExists(atPath: sourcePath, isDirectory: &isDirectoryFlag) else {
                continue
            }
            let name = source.lastPathComponent
            if Self.url(folder.url, isWithin: source) {
                plan.rejected.append(name)
                continue
            }
            let destination = folder.url.appending(path: name)
            if isCut {
                guard Self.normalizedPath(source.deletingLastPathComponent()) != Self.normalizedPath(folder.url) else {
                    continue
                }
                if Self.url(source, isWithin: destination) {
                    plan.rejected.append(name)
                    continue
                }
                let exists = fileManager.fileExists(atPath: destination.path(percentEncoded: false))
                if exists, !(confirmReplace?(name) ?? replaceFileDialog(fileName: name)) {
                    continue
                }
                plan.entries.append(
                    PasteEntry(source: source, destination: destination, isCut: true, replacesExisting: exists)
                )
            } else {
                let isDirectory = isDirectoryFlag.boolValue
                let unique = CopyNaming.uniqueURL(for: source, isDirectory: isDirectory, in: folder.url) {
                    fileManager.fileExists(atPath: $0.path(percentEncoded: false))
                }
                plan.entries.append(
                    PasteEntry(source: source, destination: unique, isCut: false, replacesExisting: false)
                )
            }
        }
        return plan
    }

    func reportPasteProblems(rejected: [String], error: (any Error)?) {
        if !rejected.isEmpty {
            let alert = NSAlert()
            alert.messageText = "Cannot paste \(rejected.joined(separator: ", ")) into itself"
            alert.addButton(withTitle: "Dismiss")
            alert.runModal()
        }
        if let error {
            showErrorAlert(error)
        }
    }

    func refresh(directories: [URL], in manager: CEWorkspaceFileManager) -> (any Error)? {
        var firstError: (any Error)?
        for directory in directories {
            do {
                try manager.refresh(directoryAt: directory)
            } catch {
                firstError = firstError ?? error
            }
        }
        return firstError
    }

    func showErrorAlert(_ error: any Error) {
        let alert = NSAlert(error: error)
        alert.addButton(withTitle: "Dismiss")
        alert.runModal()
    }

    @concurrent
    static func transfer(
        _ entries: [PasteEntry],
        using operations: ProjectNavigatorFileOperations
    ) async -> [Result<Void, any Error>] {
        entries.map { entry in
            Result {
                if entry.replacesExisting {
                    try ProjectNavigatorItemReplacement.replace(
                        entry.destination,
                        with: entry.source,
                        mode: .move,
                        using: operations
                    )
                } else if entry.isCut {
                    try operations.move(entry.source, entry.destination)
                } else {
                    try operations.copy(entry.source, entry.destination)
                }
            }
        }
    }
}
