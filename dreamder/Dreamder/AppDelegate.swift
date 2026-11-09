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
    private let logger = EditorLogging.logger(category: "AppDelegate")

    static weak var current: AppDelegate?
    private var pendingScenes: [SceneID] = []

    var documentsController: any AppDocumentControlling = NSDocumentController.shared
    var defaults: UserDefaults = .standard
    var settings: Settings = .shared
    var languageService: () -> LSPService = { LSPService.shared }
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
    var sceneOpener: (@MainActor (SceneID) -> Void)?
    var fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
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
            let request = Self.fileOpenRequest(from: url, fileExists: fileExists)
            let filePath = URL(fileURLWithPath: request.path)
            let line = request.line
            let column = request.column

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

    nonisolated struct FileOpenRequest: Equatable {
        let path: String
        let line: Int
        let column: Int
    }

    nonisolated static func fileOpenRequest(from url: URL, fileExists: (String) -> Bool) -> FileOpenRequest {
        let fullPath = URL(fileURLWithPath: url.path).path
        let parts = fullPath.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        let existingLength = (1...parts.count).reversed().first { length in
            fileExists(parts[..<length].joined(separator: ":"))
        }
        let pathLength = existingLength ?? pathLengthWithoutNumericSuffix(of: parts)
        let suffix = parts[pathLength...]
        return FileOpenRequest(
            path: parts[..<pathLength].joined(separator: ":"),
            line: suffix.first.flatMap { Int($0) } ?? 0,
            column: suffix.dropFirst().first.flatMap { Int($0) } ?? 1
        )
    }

    private nonisolated static func pathLengthWithoutNumericSuffix(of parts: [String]) -> Int {
        var length = parts.count
        while length > 1, parts.count - length < 2, Int(parts[length - 1]) != nil {
            length -= 1
        }
        return length
    }

    // MARK: - Open windows

    @IBAction func openWelcome(_ sender: Any) {
        openScene(.welcome)
    }

    @IBAction func openAbout(_ sender: Any) {
        openScene(.about)
    }

    func openScene(_ id: SceneID) {
        guard let sceneOpener else {
            if !tryFocusWindow(id: id) {
                pendingScenes.append(id)
            }
            return
        }
        sceneOpener(id)
    }

    func installSceneOpener(_ opener: @escaping @MainActor (SceneID) -> Void) {
        Self.current = self
        sceneOpener = opener
        let pending = pendingScenes
        pendingScenes = []
        pending.forEach(opener)
    }

    static func openScene(_ id: SceneID) {
        current?.openScene(id)
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

        guard defaults.object(forKey: Self.finderExtensionFilesKey) != nil else { return }

        let files = defaults.stringArray(forKey: Self.finderExtensionFilesKey) ?? []
        for filePath in files where !filePath.isEmpty {
            reopenDocument(URL(fileURLWithPath: filePath))
        }

        defaults.removeObject(forKey: Self.finderExtensionFilesKey)
    }

    /// Enable window size restoring on app relaunch after quitting.
    private func enableWindowSizeSaveOnQuit() {
        // This enables window restoring on normal quit (instead of only on force-quit).
        UserDefaults.standard.setValue(true, forKey: "NSQuitAlwaysKeepsWindows")
    }
}

extension AppDelegate {
    static let recoverWorkspacesKey = "recover.workspaces"
    static let finderExtensionFilesKey = "openInCEFiles"
}
