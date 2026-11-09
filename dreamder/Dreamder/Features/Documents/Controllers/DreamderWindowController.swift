//
//  DreamderWindowController.swift
//  Dreamder
//
//  Created by Pavel Kasila on 18.03.22.
//

import Cocoa
import SwiftUI

@Observable
final class DreamderWindowController: NSWindowController, NSToolbarDelegate, NSWindowDelegate {
    var toolbarCollapsed: Bool = false

    // These variables store the state of the windows when using "Hide interface"
    var prevLeftToolWindowHidden: Bool?
    var prevBottomToolWindowHidden: Bool?
    var prevToolbarCollapsed: Bool?

    private var panelOpen: Bool {
        [quickOpenPanel, commandPalettePanel].contains { $0?.isVisible == true }
    }

    var workspace: WorkspaceDocument?
    @ObservationIgnored var workspaceSettingsWindow: NSWindow?
    @ObservationIgnored var quickOpenPanel: SearchPanel?
    @ObservationIgnored var commandPalettePanel: SearchPanel?

    @ObservationIgnored internal var documentEditedObservation: Task<Void, Never>?
    @ObservationIgnored var markdownPasteboard: any PasteboardAccess = SystemPasteboard()
    @ObservationIgnored private var markdownClipboardOverride: (@Sendable () -> String?)?
    @ObservationIgnored var settings: Settings = .shared
    @ObservationIgnored var formatOnSaveTimeout: Duration = FormatOnSave.defaultTimeout
    @ObservationIgnored var workspaceTrust: WorkspaceTrust = .shared

    var markdownClipboard: @Sendable () -> String? {
        get {
            if let markdownClipboardOverride { return markdownClipboardOverride }
            return { [weak self] in MainActor.assumeIsolated { self?.markdownPasteboard.plainText } }
        }
        set { markdownClipboardOverride = newValue }
    }

    var workspaceHostingController: WorkspaceHostingController? {
        contentViewController as? WorkspaceHostingController
    }

    init(
        window: NSWindow?,
        workspace: WorkspaceDocument?
    ) {
        super.init(window: window)
        window?.delegate = self
        configureWindowTabbing()
        guard let workspace else { return }
        self.workspace = workspace
        window?.title = workspace.workspaceFileManager?.folderUrl.lastPathComponent ?? "Empty"
        self.toolbarCollapsed = workspace.getFromWorkspaceState(.toolbarCollapsed) as? Bool ?? false
        self.listenToDocumentEdited(workspace: workspace)
        guard let hostingController = makeWorkspaceHostingController(with: workspace) else {
            return
        }

        installContentViewController(hostingController)

        setupToolbar()
        updateToolbarVisibility()
        registerCommands()
    }

    isolated deinit {
        documentEditedObservation?.cancel()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private func configureWindowTabbing() {
        NSWindow.allowsAutomaticWindowTabbing = true
        window?.tabbingMode = .preferred
        window?.tabbingIdentifier = NSWindow.TabbingIdentifier("dreamder.workspace")
    }

    private func makeWorkspaceHostingController(with workspace: WorkspaceDocument) -> WorkspaceHostingController? {
        guard let window else {
            return nil
        }

        return WorkspaceHostingController(workspace: workspace, windowRef: window)
    }

    private func installContentViewController(_ hostingController: WorkspaceHostingController) {
        if let contentSize = window?.contentView?.frame.size, contentSize.width > 0, contentSize.height > 0 {
            hostingController.view.frame = NSRect(origin: .zero, size: contentSize)
        }
        contentViewController = hostingController
    }

    func getSelectedCodeFile() -> CodeFileDocument? {
        workspace?.editorManager?.activeEditor.selectedTab?.file.fileDocument
    }

    @IBAction func saveDocument(_ sender: Any) {
        guard let codeFile = getSelectedCodeFile() else { return }
        let formatOnSave = FormatOnSave.live(
            service: makeFormattingService(),
            timeout: formatOnSaveTimeout,
            settings: settings
        )
        if formatOnSave.shouldFormat(codeFile) {
            saveAfterFormatting(codeFile, formatOnSave: formatOnSave)
            return
        }
        codeFile.save(sender)
        workspace?.editorManager?.activeEditor.temporaryTab = nil
    }

    @IBAction func openCommandPalette(_ sender: Any) {
        guard let workspace, let state = workspace.commandsPaletteState else { return }
        if let commandPalettePanel {
            state.reset()
            if commandPalettePanel.isVisible {
                commandPalettePanel.close()
            } else {
                show(commandPalettePanel)
            }
            return
        }
        let panel = SearchPanel()
        commandPalettePanel = panel
        let contentView = QuickActionsView(state: state) { [weak self] in
            self?.closeCommandPalette()
        }
        install(contentView, in: panel)
        show(panel)
    }

    func closeCommandPalette() {
        commandPalettePanel?.close()
    }

    @IBAction func openSearchNavigator(_ sender: Any? = nil) {
        guard let workspace else { return }

        workspace.toolWindowManager.show(.find)

        Task {
            workspace.searchState?.shouldFocusSearchField = true
        }
    }

    @IBAction func openQuickly(_ sender: Any?) {
        guard let workspace, let state = workspace.openQuicklyViewModel else { return }
        if let quickOpenPanel {
            if quickOpenPanel.isVisible {
                quickOpenPanel.close()
            } else {
                show(quickOpenPanel)
            }
            return
        }
        let panel = SearchPanel()
        quickOpenPanel = panel
        let contentView = OpenQuicklyView(
            state: state,
            onClose: { [weak self] in self?.closeQuickOpen() },
            openFile: { [weak self] file in self?.openFromQuickOpen(file) }
        )
        .environment(workspace)
        install(contentView, in: panel)
        show(panel)
    }

    func closeQuickOpen() {
        quickOpenPanel?.close()
    }

    func openFromQuickOpen(_ file: CEWorkspaceFile) {
        workspace?.editorManager?.openTab(item: file)
    }

    private func install(_ contentView: some View, in panel: SearchPanel) {
        let hostingView = NSHostingView(rootView: SettingsInjector { contentView })
        hostingView.sizingOptions = [.minSize, .intrinsicContentSize, .maxSize]
        panel.contentView = hostingView
    }

    private func show(_ panel: SearchPanel) {
        window?.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(self)
    }

    @IBAction func closeCurrentTab(_ sender: Any) {
        if panelOpen { return }
        if (workspace?.editorManager?.activeEditor.tabs ?? []).isEmpty {
            closeActiveEditor(self)
        } else {
            workspace?.editorManager?.activeEditor.closeSelectedTab()
        }
    }

    @IBAction func closeActiveEditor(_ sender: Any) {
        if workspace?.editorManager?.editorLayout.findSomeEditor(
            except: workspace?.editorManager?.activeEditor
        ) == nil {
            window?.performClose(nil)
        } else {
            workspace?.editorManager?.activeEditor.close()
        }
    }

    func windowWillClose(_ notification: Notification) {
        documentEditedObservation?.cancel()
        documentEditedObservation = nil

        contentViewController = nil

        workspaceSettingsWindow?.close()
        workspaceSettingsWindow = nil
        quickOpenPanel = nil
        commandPalettePanel = nil
        workspace = nil
    }
}
