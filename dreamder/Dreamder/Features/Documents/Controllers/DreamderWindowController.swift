//
//  DreamderWindowController.swift
//  Dreamder
//
//  Created by Pavel Kasila on 18.03.22.
//

import Cocoa
import SwiftUI
@preconcurrency import Combine

@Observable
final class DreamderWindowController: NSWindowController, NSToolbarDelegate, NSWindowDelegate {
    var toolbarCollapsed: Bool = false

    // These variables store the state of the windows when using "Hide interface"
    var prevLeftToolWindowHidden: Bool?
    var prevBottomToolWindowHidden: Bool?
    var prevToolbarCollapsed: Bool?

    @ObservationIgnored private var panelOpen = false

    var workspace: WorkspaceDocument?
    @ObservationIgnored var workspaceSettingsWindow: NSWindow?
    @ObservationIgnored var quickOpenPanel: SearchPanel?
    @ObservationIgnored var commandPalettePanel: SearchPanel?

    @ObservationIgnored internal var cancellables = [AnyCancellable]()
    @ObservationIgnored internal var documentEditedObservation: Task<Void, Never>?

    var splitViewController: DreamderSplitViewController? {
        contentViewController as? DreamderSplitViewController
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
        guard let splitViewController = setupSplitView(with: workspace) else {
            return
        }

        contentViewController = splitViewController

        setupToolbar()
        updateToolbarVisibility()
        registerCommands()
    }

    isolated deinit {
        documentEditedObservation?.cancel()
        cancellables.forEach({ $0.cancel() })
        cancellables.removeAll()
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

    private func setupSplitView(with workspace: WorkspaceDocument) -> DreamderSplitViewController? {
        guard let window else {
            return nil
        }

        return DreamderSplitViewController(workspace: workspace, windowRef: window)
    }

    private func getSelectedCodeFile() -> CodeFileDocument? {
        workspace?.editorManager?.activeEditor.selectedTab?.file.fileDocument
    }

    @IBAction func saveDocument(_ sender: Any) {
        guard let codeFile = getSelectedCodeFile() else { return }
        codeFile.save(sender)
        workspace?.editorManager?.activeEditor.temporaryTab = nil
    }

    @IBAction func openCommandPalette(_ sender: Any) {
        if let workspace, let state = workspace.commandsPaletteState {
            if let commandPalettePanel {
                if commandPalettePanel.isKeyWindow {
                    commandPalettePanel.close()
                    self.panelOpen = false
                    state.reset()
                    return
                } else {
                    state.reset()
                    window?.addChildWindow(commandPalettePanel, ordered: .above)
                    commandPalettePanel.makeKeyAndOrderFront(self)
                    self.panelOpen = true
                }
            } else {
                let panel = SearchPanel()
                self.commandPalettePanel = panel
                let contentView = QuickActionsView(state: state) {
                    panel.close()
                    self.panelOpen = false
                }
                panel.contentView = NSHostingView(rootView: SettingsInjector { contentView })
                window?.addChildWindow(panel, ordered: .above)
                panel.makeKeyAndOrderFront(self)
                self.panelOpen = true
            }
        }
    }

    /// Opens the Find tool window and focuses the search field
    @IBAction func openSearchNavigator(_ sender: Any? = nil) {
        guard let workspace else { return }

        workspace.toolWindowManager.show(.find)

        DispatchQueue.main.async {
            workspace.searchState?.shouldFocusSearchField = true
        }
    }

    @IBAction func openQuickly(_ sender: Any?) {
        if let workspace, let state = workspace.openQuicklyViewModel {
            if let quickOpenPanel {
                if quickOpenPanel.isKeyWindow {
                    quickOpenPanel.close()
                    self.panelOpen = false
                    return
                } else {
                    window?.addChildWindow(quickOpenPanel, ordered: .above)
                    quickOpenPanel.makeKeyAndOrderFront(self)
                    self.panelOpen = true
                }
            } else {
                let panel = SearchPanel()
                self.quickOpenPanel = panel

                let contentView = OpenQuicklyView(state: state) {
                    panel.close()
                    self.panelOpen = false
                } openFile: { file in
                    workspace.editorManager?.openTab(item: file)
                }.environment(workspace)

                panel.contentView = NSHostingView(rootView: SettingsInjector { contentView })
                window?.addChildWindow(panel, ordered: .above)
                panel.makeKeyAndOrderFront(self)
                self.panelOpen = true
            }
        }
    }

    @IBAction func closeCurrentTab(_ sender: Any) {
        if self.panelOpen { return }
        if (workspace?.editorManager?.activeEditor.tabs ?? []).isEmpty {
            self.closeActiveEditor(self)
        } else {
            workspace?.editorManager?.activeEditor.closeSelectedTab()
        }
    }

    @IBAction func closeActiveEditor(_ sender: Any) {
        if workspace?.editorManager?.editorLayout.findSomeEditor(
            except: workspace?.editorManager?.activeEditor
        ) == nil {
            NSApp.sendAction(#selector(NSWindow.performClose(_:)), to: NSApp.keyWindow, from: nil)
        } else {
            workspace?.editorManager?.activeEditor.close()
        }
    }

    func windowWillClose(_ notification: Notification) {
        documentEditedObservation?.cancel()
        documentEditedObservation = nil
        cancellables.forEach({ $0.cancel() })
        cancellables.removeAll()

        contentViewController = nil

        workspaceSettingsWindow?.close()
        workspaceSettingsWindow = nil
        quickOpenPanel = nil
        commandPalettePanel = nil
        workspace = nil
    }
}
