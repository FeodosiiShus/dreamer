//
//  WorkspaceDocument.swift
//  Dreamder
//
//  Created by Pavel Kasila on 17.03.22.
//

import AppKit
import SwiftUI
import Foundation
import LanguageServerProtocol

@objc(WorkspaceDocument)
@Observable
final class WorkspaceDocument: NSDocument, NSToolbarDelegate {
    var sortFoldersOnTop: Bool = true
    /// A string used to filter the displayed files and folders in the project navigator area based on user input.
    var navigatorFilter: String = ""
    /// Whether the workspace only shows files with changes.
    var sourceControlFilter = false

    @ObservationIgnored private var transientWorkspaceState: [String: Any] = [:]
    @ObservationIgnored var stateDefaults: UserDefaults = .standard

    static func workspaceStateKey(for url: URL) -> String {
        "workspaceState-\(url.standardizedFileURL.absoluteString)"
    }

    private var workspaceState: [String: Any] {
        get {
            guard let key = fileURL.map(Self.workspaceStateKey(for:)) else { return transientWorkspaceState }
            return stateDefaults.object(forKey: key) as? [String: Any] ?? [:]
        }
        set {
            guard let key = fileURL.map(Self.workspaceStateKey(for:)) else {
                transientWorkspaceState = newValue
                return
            }
            stateDefaults.set(newValue, forKey: key)
        }
    }

    @ObservationIgnored var workspaceFileManager: CEWorkspaceFileManager?

    var editorManager: EditorManager? = EditorManager()
    var statusBarViewModel: StatusBarViewModel? = StatusBarViewModel()
    var utilityAreaModel: UtilityAreaViewModel? = UtilityAreaViewModel()
    var searchState: SearchState?
    var openQuicklyViewModel: OpenQuicklyViewModel?
    var commandsPaletteState: QuickActionsViewModel?
    var listenerModel: WorkspaceNotificationModel = .init()
    var sourceControlManager: SourceControlManager?
    @ObservationIgnored private(set) var excludedDirectories: ExcludedDirectories?
    @ObservationIgnored var fileScope: WorkspaceFileScope?
    @ObservationIgnored var symbolIndex: SearchEverywhereSymbolIndex?
    @ObservationIgnored var fileScopeObserver: WorkspaceFileScopeObserver?
    @ObservationIgnored var fileScopeTasks: [Task<Void, Never>] = []

    @ObservationIgnored var taskManager: TaskManager?
    @ObservationIgnored var workspaceSettingsManager: CEWorkspaceSettings?
    @ObservationIgnored var taskNotificationHandler: TaskNotificationHandler = TaskNotificationHandler()

    @ObservationIgnored var undoRegistration: UndoManagerRegistration = UndoManagerRegistration()

    var notificationPanel = NotificationPanelViewModel()
    let toolWindowManager = ToolWindowManager()
    let diagnosticsStore = DiagnosticsStore()

    override init() {
        super.init()
        notificationPanel.workspace = self
    }

    isolated deinit {
        NotificationCenter.default.removeObserver(self)
        fileScopeTasks.forEach { $0.cancel() }
        fileScope?.cleanUp()
    }

    func getFromWorkspaceState(_ key: WorkspaceStateKey) -> Any? {
        return workspaceState[key.rawValue]
    }

    func addToWorkspaceState(key: WorkspaceStateKey, value: Any?) {
        if let value {
            workspaceState.updateValue(value, forKey: key.rawValue)
        } else {
            workspaceState.removeValue(forKey: key.rawValue)
        }
    }

    // MARK: NSDocument

    private let ignoredFilesAndDirectory = [
        ".DS_Store"
    ]

    nonisolated override static var autosavesInPlace: Bool {
        false
    }

    override var isDocumentEdited: Bool {
        false
    }

    override func makeWindowControllers() {
        makeWorkspaceWindow().makeKeyAndOrderFront(nil)
    }

    func makeWorkspaceWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1400, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        // Note For anyone hoping to switch back to a Root-SwiftUI window:
        // See Commit 0200c87 for more details and to see what was previously here.
        // -----
        // Setting the "min size" like this is hacky, but SwiftUI overrides the contentRect and
        // any of the built-in window size functions & autosave stuff. So we have to set it like this.
        // SwiftUI also ignores this value, so it just manages to set the initial window size. *Hopefully* this
        // is fixed in the future.
        // ----
        let windowController = DreamderWindowController(
            window: window,
            workspace: self
        )

        if let rectString = getFromWorkspaceState(.workspaceWindowSize) as? String {
            window.setFrame(NSRectFromString(rectString), display: true, animate: false)
        } else {
            window.setFrame(NSRect(x: 0, y: 0, width: 1400, height: 900), display: true, animate: false)
            window.center()
        }

        window.setAccessibilityIdentifier("workspace")
        window.setAccessibilityDocument(self.fileURL?.absoluteString)

        self.addWindowController(windowController)
        return window
    }

    // MARK: Set Up Workspace

    private func initWorkspaceState(_ url: URL) throws {
        // Ensure the URL ends with a "/" to prevent certain URL(filePath:relativeTo) initializers from
        // placing the file one directory above our workspace. This quick fix appends a "/" if needed.
        var url = url
        if !url.absoluteString.hasSuffix("/") {
            url = URL(filePath: url.absoluteURL.path(percentEncoded: false) + "/")
        }

        self.fileURL = url
        self.displayName = url.lastPathComponent
        self.excludedDirectories = ExcludedDirectories(rootURL: url)

        guard let editorManager else {
            throw CocoaError(.fileReadUnknown)
        }

        let sourceControlManager = SourceControlManager(
            workspaceURL: url,
            editorManager: editorManager
        )

        self.workspaceFileManager = .init(
            folderUrl: url,
            ignoredFilesAndFolders: Set(ignoredFilesAndDirectory),
            sourceControlManager: sourceControlManager
        )
        self.sourceControlManager = sourceControlManager
        sourceControlManager.fileManager = workspaceFileManager
        configureFileScope(rootURL: url)
        self.searchState = .init(self)
        self.openQuicklyViewModel = .init(fileURL: url, scope: fileScope)
        self.commandsPaletteState = .init()
        self.workspaceSettingsManager = CEWorkspaceSettings(workspaceURL: url)
        if let workspaceSettingsManager {
            self.taskManager = TaskManager(
                workspaceSettings: workspaceSettingsManager.settings,
                workspaceURL: url
            )
        }
        self.taskNotificationHandler.workspaceURL = url

        workspaceFileManager?.addObserver(undoRegistration)
        editorManager.restoreFromState(self)
        utilityAreaModel?.restoreFromState(self)
    }

    nonisolated override func read(from url: URL, ofType typeName: String) throws {
        try MainActor.assumeIsolated {
            try initWorkspaceState(url)
        }
    }

    nonisolated override func write(to url: URL, ofType typeName: String) throws {}

    // MARK: Close Workspace

    override func close() {
        super.close()
        editorManager?.saveRestorationState(self)
        utilityAreaModel?.saveRestorationState(self)
        if let utilityAreaModel {
            utilityAreaModel.removeTerminals(Set(utilityAreaModel.terminals.map(\.id)))
        }
        closeOpenCodeFiles()

        statusBarViewModel = nil
        utilityAreaModel = nil
        searchState = nil
        editorManager = nil
        openQuicklyViewModel = nil
        commandsPaletteState = nil
        sourceControlManager = nil
        workspaceFileManager?.cleanUp()
        workspaceFileManager = nil
        tearDownFileScope()
        workspaceSettingsManager?.cleanUp()
        workspaceSettingsManager = nil
        taskManager?.terminateAllTasks()
        taskManager = nil
    }

    override func shouldCloseWindowController(
        _ windowController: NSWindowController,
        delegate: Any?,
        shouldClose shouldCloseSelector: Selector?,
        contextInfo: UnsafeMutableRawPointer?
    ) {
        guard let object = (delegate as? NSObject),
              let shouldCloseSelector = shouldCloseSelector
        else {
            super.shouldCloseWindowController(
                windowController,
                delegate: nil,
                shouldClose: nil,
                contextInfo: contextInfo
            )
            return
        }
        let answer: (Bool) -> Void = { shouldClose in
            DocumentCloseCallback.invoke(
                on: object,
                selector: shouldCloseSelector,
                document: self,
                shouldClose: shouldClose,
                contextInfo: contextInfo
            )
        }
        guard let editorManager else {
            answer(false)
            return
        }
        DocumentCloseConfirmation.ask(openCodeFiles(in: editorManager), completion: answer)
    }

    func isShowing(_ document: CodeFileDocument) -> Bool {
        editorManager?.editorLayout.gatherOpenFiles().contains { $0.fileDocument === document } ?? false
    }

    private func openCodeFiles(in editorManager: EditorManager) -> [CodeFileDocument] {
        var seen = Set<ObjectIdentifier>()
        return editorManager.editorLayout.gatherOpenFiles()
            .sorted { $0.url.path < $1.url.path }
            .compactMap(\.fileDocument)
            .filter { seen.insert(ObjectIdentifier($0)).inserted }
    }

    private func closeOpenCodeFiles() {
        for file in editorManager?.editorLayout.gatherOpenFiles() ?? [] {
            guard let document = file.fileDocument else { continue }
            file.fileDocument = nil
            if !document.isInUse(outside: self) {
                document.close()
            }
        }
    }
}
