import SwiftUI

extension AppDelegate {
    // MARK: NSDocumentController delegate

    @objc
    func documentController(
        _ docController: NSDocumentController,
        didCloseAll: Bool,
        contextInfo: UnsafeMutableRawPointer?
    ) {
        guard didCloseAll else {
            replyToTerminate(false)
            return
        }
        terminateTasks()
        terminateLanguageServers()
    }

    /// Terminates running language servers. Used during app termination to ensure resources are freed.
    private func terminateLanguageServers() {
        let timeout = languageServerShutdownTimeout
        Task { @MainActor in
            let service = self.languageService()
            let task = TaskNotificationModel(
                id: "appdelegate.terminate_language_servers",
                title: "Stopping Language Servers",
                message: "Stopping running language server processes...",
                isLoading: true
            )

            if !service.languageClients.isEmpty {
                TaskNotificationHandler.postTask(action: .create, model: task)
            }

            try? await withTimeout(
                duration: timeout,
                onTimeout: {
                    // Stop-gap measure to ensure we don't hang on CMD-Q
                    await service.killAllServers()
                },
                operation: {
                    await service.stopAllServers()
                }
            )

            TaskNotificationHandler.postTask(action: .delete, model: task)
            self.replyToTerminate(true)
        }
    }

    /// Terminates all running tasks. Used during app termination to ensure resources are freed.
    private func terminateTasks() {
        let task = TaskNotificationModel(
            id: "appdelegate.terminate_tasks",
            title: "Terminating Tasks",
            message: "Interrupting all running tasks before quitting...",
            isLoading: true
        )

        let taskManagers = documentsController.documents
            .compactMap({ $0 as? WorkspaceDocument })
            .compactMap({ $0.taskManager })

        if taskManagers.reduce(0, { $0 + $1.activeTasks.count }) > 0 {
            TaskNotificationHandler.postTask(action: .create, model: task)
        }

        taskManagers.forEach { manager in
            manager.stopAllTasks()
        }

        TaskNotificationHandler.postTask(action: .delete, model: task)
    }

    // MARK: - Should Terminate

    /// Defers the application terminate message until we've finished cleanup.
    ///
    /// All paths _must_ call `NSApplication.shared.reply(toApplicationShouldTerminate: true)` as soon as possible.
    ///
    /// The two things needing deferring are:
    /// - Language server cancellation
    /// - Outstanding document changes.
    ///
    /// Things that don't need deferring (happen immediately):
    /// - Task termination.
    /// These are called immediately if no documents need closing, and are called by
    /// ``documentController(_:didCloseAll:contextInfo:)`` if there are documents we need to defer for.
    ///
    /// See ``terminateLanguageServers()`` and ``documentController(_:didCloseAll:contextInfo:)`` for deferring tasks.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let projects: [String] = documentsController.documents
            .compactMap { ($0 as? WorkspaceDocument)?.fileURL?.path }

        defaults.set(projects, forKey: AppDelegate.recoverWorkspacesKey)

        let areAllDocumentsClean = documentsController.documents.allSatisfy { !$0.isDocumentEdited }
        guard areAllDocumentsClean else {
            documentsController.closeAllDocuments(
                withDelegate: self,
                didCloseAllSelector: #selector(documentController(_:didCloseAll:contextInfo:)),
                contextInfo: nil
            )
            // `documentController(_:didCloseAll:contextInfo:)` will call `terminateLanguageServers()`
            return .terminateLater
        }

        terminateTasks()
        terminateLanguageServers()
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        settings.flushPendingSave()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
