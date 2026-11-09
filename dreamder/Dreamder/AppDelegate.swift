//
//  AppDelegate.swift
//  Dreamder
//
//  Created by Pavel Kasila on 12.03.22.
//

import SwiftUI
import CodeEditSymbols
import CodeEditSourceEditor
import OSLog

@MainActor
protocol AppDocumentControlling: AnyObject {
    var documents: [NSDocument] { get }
    func openDocument(
        withContentsOf url: URL,
        display displayDocument: Bool,
        completionHandler: @escaping (NSDocument?, Bool, (any Error)?) -> Void
    )
    func openDocument(_ sender: Any?)
    func newDocument(_ sender: Any?)
    func closeAllDocuments(
        withDelegate delegate: Any?,
        didCloseAllSelector: Selector?,
        contextInfo: UnsafeMutableRawPointer?
    )
}

extension NSDocumentController: AppDocumentControlling {}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "dev.dreamder.Dreamder",
        category: "AppDelegate"
    )

    @Environment(\.openWindow)
    var openWindow

    var documentsController: any AppDocumentControlling = NSDocumentController.shared
    var defaults: UserDefaults = .standard
    var settings: Settings = .shared
    var languageServiceOverride: LSPService?
    var replyToTerminate: (Bool) -> Void = { NSApplication.shared.reply(toApplicationShouldTerminate: $0) }
    var reopenDocument: (URL) -> Void = { url in
        DreamderDocumentController.shared.reopenDocument(
            for: url,
            withContentsOf: url,
            display: true
        ) { document, _, _ in
            AppDelegate.synchronizeWindowTitle(of: document)
        }
    }
    var sceneOpenerOverride: ((SceneID) -> Void)?
    var applicationWindows: () -> [NSWindow] = { NSApp.windows }
    var finderExtensionDefaults: () -> UserDefaults? = { UserDefaults(suiteName: "dev.dreamder.Dreamder.shared") }
    var finderExtensionPollInterval: Duration = .seconds(1)
    var languageServerShutdownTimeout: Duration = .seconds(2)
    private var finderExtensionPolling: Task<Void, Never>?

    isolated deinit {
        finderExtensionPolling?.cancel()
    }

    static func synchronizeWindowTitle(of document: NSDocument?) {
        document?.windowControllers.first?.synchronizeWindowTitleWithDocumentName()
    }

    nonisolated static func openURLs(fromArguments arguments: [String]) -> [URL] {
        arguments.indices.compactMap { index in
            guard arguments[index] == "--open", index + 1 < arguments.count else { return nil }
            return URL(fileURLWithPath: arguments[index + 1])
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DreamderHeadless.install()
        DreamderAutomation.install()
        SearchEverywhereShiftMonitor.shared.install()
        enableWindowSizeSaveOnQuit()
        settings.preferences.general.appAppearance.applyAppearance()
        startPollingFinderExtensionRequests()

        NSApp.closeWindow(.welcome, .about)

        Task { @MainActor in
            // If no windows were reopened by NSQuitAlwaysKeepsWindows, do default behavior.
            // Non-WindowGroup SwiftUI Windows are still in NSApp.windows when they are closed,
            // So we need to think about those.
            openInitialDocuments(
                arguments: CommandLine.arguments,
                windowsWereReopened: NSApp.windows.count > NSApp.openSwiftUIWindows
            )
        }
    }

    func openInitialDocuments(arguments: [String], windowsWereReopened: Bool) {
        var needToHandleOpen = !windowsWereReopened

        for url in Self.openURLs(fromArguments: arguments) {
            reopenDocument(url)
            needToHandleOpen = false
        }

        if needToHandleOpen {
            handleOpen()
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard flag else {
            handleOpen()
            return false
        }

        restoreMiniaturizedWindow(in: sender.windows, sender: sender)
        return false
    }

    func restoreMiniaturizedWindow(in windows: [NSWindow], sender: Any?) {
        /// Check if all windows are either miniaturized or not visible.
        /// If so, attempt to find the first miniaturized window and deminiaturize it.
        guard windows.allSatisfy({ $0.isMiniaturized || !$0.isVisible }) else { return }
        windows.first(where: { $0.isMiniaturized })?.deminiaturize(sender)
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        false
    }

    func handleOpen() {
        let behavior = settings.preferences.general.reopenBehavior
        switch behavior {
        case .welcome:
            if !tryFocusWindow(id: .welcome) {
                openScene(.welcome)
            }
        case .openPanel:
            documentsController.openDocument(self)
        case .newDocument:
            documentsController.newDocument(self)
        }
    }

    /// Handle urls with the form `dreamder://file/{filepath}:{line}:{column}`
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            let file = URL(fileURLWithPath: url.path).path.split(separator: ":")
            let filePath = URL(fileURLWithPath: String(file[0]))
            let line = file.count > 1 ? Int(file[1]) ?? 0 : 0
            let column = file.count > 2 ? Int(file[2]) ?? 1 : 1

            documentsController
                .openDocument(withContentsOf: filePath, display: true) { document, _, error in
                    if let error {
                        NSAlert(error: error).runModal()
                        return
                    }
                    if line > 0, let document = document as? CodeFileDocument {
                        document.openOptions = CodeFileDocument.OpenOptions(
                            cursorPositions: [CursorPosition(line: line, column: column > 0 ? column : 1)]
                        )
                    }
                }
        }
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

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Open windows

    @IBAction func openWelcome(_ sender: Any) {
        openScene(.welcome)
    }

    @IBAction func openAbout(_ sender: Any) {
        openScene(.about)
    }

    func openScene(_ id: SceneID) {
        if let sceneOpenerOverride {
            sceneOpenerOverride(id)
        } else {
            openWindow(sceneID: id)
        }
    }

    /// Tries to focus a window with specified sceneId
    /// - Parameter type: Id of a window to be focused.
    /// - Returns: `true` if window exist and focused, otherwise - `false`
    private func tryFocusWindow(id: SceneID) -> Bool {
        guard let window = applicationWindows().first(where: { $0.identifier?.rawValue == id.rawValue })
        else { return false }

        window.makeKeyAndOrderFront(self)
        return true
    }

    // MARK: - Open With Dreamder (Extension) functions
    func startPollingFinderExtensionRequests() {
        finderExtensionPolling?.cancel()
        let interval = finderExtensionPollInterval
        finderExtensionPolling = Task { [weak self] in
            while !Task.isCancelled, self?.checkForFilesToOpen() == true {
                try? await Task.sleep(for: interval)
            }
        }
    }

    func checkForFilesToOpen() -> Bool {
        guard let defaults = finderExtensionDefaults() else {
            logger.error("Failed to get/init shared defaults")
            return false
        }

        openFilesRequestedByFinderExtension(defaults: defaults)
        return true
    }

    func openFilesRequestedByFinderExtension(defaults: UserDefaults) {
        // Register enableOpenInCE (enable Open In Dreamder
        defaults.register(defaults: ["enableOpenInCE": true])

        if let filesToOpen = defaults.string(forKey: "openInCEFiles") {
            let files = filesToOpen.split(separator: ";")

            for filePath in files {
                reopenDocument(URL(fileURLWithPath: String(filePath)))
            }

            defaults.removeObject(forKey: "openInCEFiles")
        }
    }

    /// Enable window size restoring on app relaunch after quitting.
    private func enableWindowSizeSaveOnQuit() {
        // This enables window restoring on normal quit (instead of only on force-quit).
        UserDefaults.standard.setValue(true, forKey: "NSQuitAlwaysKeepsWindows")
    }

    // MARK: NSDocumentController delegate

    @objc
    func documentController(_ docController: NSDocumentController, didCloseAll: Bool, contextInfo: Any) {
        if didCloseAll {
            terminateTasks()
            terminateLanguageServers()
        }
    }

    /// Terminates running language servers. Used during app termination to ensure resources are freed.
    private func terminateLanguageServers() {
        let timeout = languageServerShutdownTimeout
        Task { @MainActor in
            let service = self.languageServiceOverride ?? LSPService.shared
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
}

extension AppDelegate {
    static let recoverWorkspacesKey = "recover.workspaces"
}
