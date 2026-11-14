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

    lazy var lspService: LSPService = .shared

    var recentProjects = RecentProjectsManager.shared

    var settings = Settings.shared

    var openDocuments: @MainActor () -> [NSDocument] = { DreamderDocumentController.shared.documents }

    var showWelcomeWindow: @MainActor () -> Void = {
        AppDelegate.openScene(.welcome)
    }

    var quitApplication: @MainActor () -> Void = { NSApplication.shared.terminate(nil) }

    private let fileManager = FileManager.default

    var recordsRecentDocuments = !DreamderHeadless.isEnabled

    override func noteNewRecentDocument(_ document: NSDocument) {
        if recordsRecentDocuments { super.noteNewRecentDocument(document) }
    }

    override func noteNewRecentDocumentURL(_ url: URL) {
        if recordsRecentDocuments { super.noteNewRecentDocumentURL(url) }
    }

    func noteRecentProject(at url: URL) {
        noteRecentProject(at: url, recording: recordsRecentDocuments, in: recentProjects)
    }

    func noteRecentProject(at url: URL, recording: Bool, in manager: RecentProjectsManager) {
        if recording { recordRecentProject(at: url, in: manager) }
    }

    func recordRecentProject(at url: URL, in manager: RecentProjectsManager) {
        manager.markRecent(at: url, isDirectory: url.isFolder)
    }

    @MainActor
    @discardableResult
    func createAndOpenNewDocument() async -> Bool {
        await createAndOpenNewDocument(panels: filePanels)
    }

    @MainActor
    @discardableResult
    func createAndOpenNewDocument(panels: any FilePanelPresenting) async -> Bool {
        guard let url = createNewDocumentFile(panels: panels) else { return false }
        await withCheckedContinuation { continuation in
            openDocument(withContentsOf: url, display: true) { _, _, _ in
                continuation.resume()
            }
        }
        return true
    }

    override func newDocument(_ sender: Any?) {
        createNewDocument(panels: filePanels)
    }

    func createNewDocument(panels: any FilePanelPresenting) {
        guard let url = createNewDocumentFile(panels: panels) else { return }
        openDocument(withContentsOf: url, display: true) { _, _, _ in }
    }

    private func createNewDocumentFile(panels: any FilePanelPresenting) -> URL? {
        guard let url = panels.chooseSaveLocation(SavePanelRequest()) else { return nil }
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
        openDocument(panels: filePanels)
    }

    func openDocument(panels: any FilePanelPresenting) {
        openDocument(onCompletion: { _, _ in }, onCancel: {}, panels: panels)
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
                self.finishOpening(
                    url: url,
                    document: document,
                    alreadyOpen: documentWasAlreadyOpen,
                    error: error,
                    completionHandler: completionHandler
                )
            }
        }
    }

    func finishOpening(
        url: URL,
        document: NSDocument?,
        alreadyOpen: Bool,
        error: Error?,
        completionHandler: (NSDocument?, Bool, Error?) -> Void
    ) {
        if let document {
            addDocument(document)
        } else {
            let errorMessage = error?.localizedDescription ?? "unknown error"
            Self.logger.error(
                "Unable to open document '\(url.path, privacy: .public)': \(errorMessage, privacy: .public)"
            )
        }

        noteRecentProject(at: url)
        completionHandler(document, alreadyOpen, error)
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
        finishRemoval(
            of: document,
            context: DocumentRemovalContext(
                lspService: lspService,
                openDocuments: openDocuments,
                settings: settings,
                showWelcomeWindow: showWelcomeWindow,
                quitApplication: quitApplication
            )
        )
    }

    func finishRemoval(of document: NSDocument, context: DocumentRemovalContext) {
        if let workspace = document as? WorkspaceDocument, let path = workspace.fileURL?.absolutePath {
            context.lspService.closeWorkspace(path)
        }

        guard context.openDocuments().isEmpty else { return }
        switch context.settings.preferences.general.reopenWindowAfterClose {
        case .showWelcomeWindow: context.showWelcomeWindow()
        case .quit: context.quitApplication()
        case .doNothing: break
        }
    }
}
