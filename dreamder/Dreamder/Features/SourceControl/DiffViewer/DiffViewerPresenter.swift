import AppKit
import Foundation

@MainActor
enum DiffViewerPresenter {
    private static var windows: [String: DiffViewerWindowController] = [:]

    static func showFileDiff(workspace: WorkspaceDocument, fileURL: URL, against ref: String = "HEAD") {
        guard let repository = DiffRepository(workspace: workspace) else { return }
        let path = DiffPath.relativePath(of: fileURL, from: repository.rootURL)
        guard !path.isEmpty else { return }

        let key = "worktree:\(ref):\(path)"
        if focus(key) { return }

        let changedFile = workspace.sourceControlManager?.changedFiles.first {
            DiffPath.relativePath(of: $0.fileURL, from: repository.rootURL) == path
        }
        let request = repository.workingTreeRequest(
            status: changedFile?.anyStatus() ?? .modified,
            path: path,
            originalPath: changedFile?.originalFilename,
            ref: ref
        )
        let model = DiffViewerViewModel(
            repository: repository,
            mode: .workingTree(ref: ref),
            files: [request]
        )
        present(model, key: key, parent: workspace.windowControllers.first?.window)
    }

    static func showWorkingTreeDiff(workspace: WorkspaceDocument, against ref: String) {
        guard let repository = DiffRepository(workspace: workspace) else { return }

        let key = "worktree-all:\(ref)"
        Task { @MainActor in
            do {
                let files = try await repository.workingTreeRequests(against: ref)
                if let controller = windows[key], let window = controller.window {
                    controller.update(files: files)
                    NSApp.activate()
                    window.makeKeyAndOrderFront(nil)
                    return
                }
                guard !files.isEmpty else {
                    showAlert(
                        title: "No Differences",
                        message: "There are no local changes compared to \(ref)."
                    )
                    return
                }
                let model = DiffViewerViewModel(
                    repository: repository,
                    mode: .workingTree(ref: ref),
                    files: files
                )
                present(model, key: key, parent: workspace.windowControllers.first?.window)
            } catch {
                showAlert(title: "Failed to load changes", message: describe(error))
            }
        }
    }

    static func showCommitFileDiff(
        workspace: WorkspaceDocument,
        commitHash: String,
        parentHash: String?,
        path: String
    ) {
        guard let repository = DiffRepository(workspace: workspace), !path.isEmpty else { return }

        let key = "commit:\(commitHash):\(parentHash ?? ""):\(path)"
        if focus(key) { return }

        let request = repository.commitRequest(
            path: path,
            status: .modified,
            commit: commitHash,
            parent: parentHash
        )
        let model = DiffViewerViewModel(
            repository: repository,
            mode: .commit(hash: commitHash, parentHash: parentHash),
            files: [request]
        )
        present(model, key: key, parent: workspace.windowControllers.first?.window)
    }

    private static func focus(_ key: String) -> Bool {
        guard let controller = windows[key], let window = controller.window else { return false }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        controller.reload()
        return true
    }

    private static func present(_ model: DiffViewerViewModel, key: String, parent: NSWindow?) {
        let controller = DiffViewerWindowController(model: model)
        controller.onClose = {
            windows[key] = nil
        }
        windows[key] = controller
        controller.place(relativeTo: parent)
        controller.showWindow(nil)
        NSApp.activate()
    }

    private static func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.alertStyle = .informational
        alert.runModal()
    }

    private static func describe(_ error: Error) -> String {
        if let gitError = error as? GitClient.GitClientError {
            return gitError.description
        }
        return error.localizedDescription
    }
}
