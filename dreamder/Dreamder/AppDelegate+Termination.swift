import SwiftUI

extension AppDelegate {
    // MARK: NSDocumentController delegate

    @objc
    func documentController(
        _ docController: NSDocumentController,
        didCloseAll: Bool,
        contextInfo: UnsafeMutableRawPointer?
    ) {
        let taskManagers = QuitTaskManagers.take(from: contextInfo)
        guard didCloseAll else {
            replyToTerminate(false)
            return
        }
        finishTermination(taskManagers: taskManagers)
    }

    private func finishTermination(taskManagers: [TaskManager]) {
        Task { @MainActor in
            await self.terminateTasks(of: taskManagers)
            await self.terminateLanguageServers()
            self.replyToTerminate(true)
        }
    }

    /// Terminates running language servers. Used during app termination to ensure resources are freed.
    private func terminateLanguageServers() async {
        let timeout = languageServerShutdownTimeout
        let service = languageService()
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
    }

    /// Terminates all running tasks. Used during app termination to ensure resources are freed.
    private func terminateTasks(of taskManagers: [TaskManager]) async {
        let task = TaskNotificationModel(
            id: "appdelegate.terminate_tasks",
            title: "Terminating Tasks",
            message: "Interrupting all running tasks before quitting...",
            isLoading: true
        )

        if taskManagers.contains(where: { $0.hasActiveTasks }) {
            TaskNotificationHandler.postTask(action: .create, model: task)
        }

        await withTaskGroup(of: Void.self) { group in
            for manager in taskManagers {
                group.addTask { await manager.shutDownTasks() }
            }
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
        let taskManagers = documentsController.documents
            .compactMap { ($0 as? WorkspaceDocument)?.taskManager }

        defaults.set(projects, forKey: AppDelegate.recoverWorkspacesKey)

        let areAllDocumentsClean = documentsController.documents.allSatisfy { !$0.isDocumentEdited }
        guard areAllDocumentsClean else {
            documentsController.closeAllDocuments(
                withDelegate: self,
                didCloseAllSelector: #selector(documentController(_:didCloseAll:contextInfo:)),
                contextInfo: QuitTaskManagers(taskManagers).retainedPointer()
            )
            // `documentController(_:didCloseAll:contextInfo:)` will call `terminateLanguageServers()`
            return .terminateLater
        }

        finishTermination(taskManagers: taskManagers)
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        settings.flushPendingSave()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

private final class QuitTaskManagers {
    let taskManagers: [TaskManager]

    init(_ taskManagers: [TaskManager]) {
        self.taskManagers = taskManagers
    }

    func retainedPointer() -> UnsafeMutableRawPointer {
        Unmanaged.passRetained(self).toOpaque()
    }

    static func take(from pointer: UnsafeMutableRawPointer?) -> [TaskManager] {
        pointer.map { Unmanaged<QuitTaskManagers>.fromOpaque($0).takeRetainedValue().taskManagers } ?? []
    }
}
