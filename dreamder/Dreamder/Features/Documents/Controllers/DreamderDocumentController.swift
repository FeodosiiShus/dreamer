//
//  DreamderDocumentController.swift
//  Dreamder
//
//  Created by Pavel Kasila on 17.03.22.
//

import Cocoa
import OSLog
import SwiftUI

final class DreamderDocumentController: NSDocumentController {
    private static let logger = Logger(subsystem: "dev.dreamder.Dreamder", category: "DreamderDocumentController")

    var lspService: LSPService { .shared }

    var recentProjects = RecentProjectsManager.shared

    var settings = Settings.shared

    var openDocuments: @MainActor () -> [NSDocument] = { DreamderDocumentController.shared.documents }

    var showWelcomeWindow: @MainActor () -> Void = {
        (NSApp.delegate as? AppDelegate)?.openWindow(sceneID: .welcome)
    }

    var quitApplication: @MainActor () -> Void = { NSApplication.shared.terminate(nil) }

    private let fileManager = FileManager.default

    var recordsRecentDocuments: Bool {
        !DreamderHeadless.isEnabled
    }

    override func noteNewRecentDocument(_ document: NSDocument) {
        if recordsRecentDocuments { super.noteNewRecentDocument(document) }
    }

    override func noteNewRecentDocumentURL(_ url: URL) {
        if recordsRecentDocuments { super.noteNewRecentDocumentURL(url) }
    }

    func noteRecentProject(at url: URL) {
        if recordsRecentDocuments { recordRecentProject(at: url) }
    }

    func recordRecentProject(at url: URL) {
        recentProjects.markRecent(at: url, isDirectory: url.isFolder)
    }

    @MainActor
    @discardableResult
    func createAndOpenNewDocument() async -> Bool {
        guard let url = createNewDocumentFile() else { return false }
        await withCheckedContinuation { continuation in
            openDocument(withContentsOf: url, display: true) { _, _, _ in
                continuation.resume()
            }
        }
        return true
    }

    override func newDocument(_ sender: Any?) {
        guard let url = createNewDocumentFile() else { return }
        openDocument(withContentsOf: url, display: true) { _, _, _ in }
    }

    private func createNewDocumentFile() -> URL? {
        guard let url = filePanels.chooseSaveLocation(SavePanelRequest()) else { return nil }
        let createdFile = fileManager.createFile(
            atPath: url.path,
            contents: nil,
            attributes: [FileAttributeKey.creationDate: Date()]
        )
        guard createdFile else {
            Self.logger.error("Failed to create new document at \(url.path, privacy: .public)")
            return nil
        }
        return url
    }

    var filePanels: any FilePanelPresenting = SystemFilePanels()

    override func openDocument(_ sender: Any?) {
        openDocument(onCompletion: { _, _ in }, onCancel: {}, panels: filePanels)
    }

    override func openDocument(
        withContentsOf url: URL,
        display displayDocument: Bool,
        completionHandler: @escaping (NSDocument?, Bool, Error?) -> Void
    ) {
        if let workspace = openFileInExistingWorkspace(url: url) {
            completionHandler(workspace, true, nil)
            return
        }

        super.openDocument(withContentsOf: url, display: displayDocument) { document, documentWasAlreadyOpen, error in
            MainActor.assumeIsolated {
                if let document {
                    self.addDocument(document)
                } else {
                    let errorMessage = error?.localizedDescription ?? "unknown error"
                    Self.logger.error(
                        "Unable to open document '\(url.path, privacy: .public)': \(errorMessage, privacy: .public)"
                    )
                }

                self.noteRecentProject(at: url)
                completionHandler(document, documentWasAlreadyOpen, error)
            }
        }
    }

    /// Attempt to open the file URL in an open workspace, finding the nearest workspace to open it in if possible.
    /// - Parameter url: The file URL to open.
    /// - Returns: The workspace that opened the file, or `nil` if no open workspace contains it.
    private func openFileInExistingWorkspace(url: URL) -> WorkspaceDocument? {
        guard !url.isFolder else { return nil }
        let workspaces = documents.compactMap({ $0 as? WorkspaceDocument })

        // Check open workspaces for the file being opened. Sorted by shared components with the url so we
        // open the nearest workspace possible.
        for workspace in workspaces.sorted(by: {
            ($0.fileURL?.sharedComponents(url) ?? 0) > ($1.fileURL?.sharedComponents(url) ?? 0)
        }) {
            // createIfNotFound will still return `nil` if the files don't share a common ancestor.
            if let newFile = workspace.workspaceFileManager?.getFile(url.absolutePath, createIfNotFound: true) {
                workspace.editorManager?.openTab(item: newFile)
                workspace.showWindows()
                return workspace
            }
        }
        return nil
    }

    override func removeDocument(_ document: NSDocument) {
        super.removeDocument(document)

        if let workspace = document as? WorkspaceDocument, let path = workspace.fileURL?.absoluteURL.path() {
            lspService.closeWorkspace(path)
        }

        guard openDocuments().isEmpty else { return }
        switch settings.preferences.general.reopenWindowAfterClose {
        case .showWelcomeWindow: showWelcomeWindow()
        case .quit: quitApplication()
        case .doNothing: break
        }
    }
}
