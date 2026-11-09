//
//  FileCommands.swift
//  Dreamder
//
//  Created by Wouter Hennen on 13/03/2023.
//

import SwiftUI

struct FileCommands: Commands {
    static let recentProjectsMenu = RecentProjectsMenu()

    @Environment(\.openWindow)
    private var openWindow

    @UpdatingWindowController var windowController

    @FocusedValue(UtilityAreaViewModel.self) var utilityAreaViewModel: UtilityAreaViewModel?

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Group {
                DocumentButtons()

                // Leave this empty, is done through a hidden API in WindowCommands/Utils/CommandsFixes.swift
                // We set this with a custom NSMenu. See WindowCommands/Utils/RecentProjectsMenu.swift
                Menu("Open Recent") { }
            }
        }

        CommandGroup(replacing: .saveItem) {
            CloseButtons()

            CloseTerminalButton(utilityAreaViewModel: utilityAreaViewModel)

            Divider()

            WorkspaceButtons(isWorkspaceSettingsEnabled: windowController?.workspace != nil)
        }
    }
}

extension FileCommands {
    struct DocumentButtons: View {
        var documentController: any AppDocumentControlling = NSDocumentController.shared

        var body: some View {
            Button("New") {
                documentController.newDocument(nil)
            }
            .keymapShortcut(.newDocument)

            Button("Open...") {
                documentController.openDocument(nil)
            }
            .keymapShortcut(.openDocument)
        }
    }

    struct CloseButtons: View {
        var responderForAction: @MainActor (Selector) -> Any? = { NSApp.target(forAction: $0) }
        var keyWindow: @MainActor () -> NSWindow? = { NSApp.keyWindow }

        var body: some View {
            Button("Close Tab") {
                closeOrPerformClose(#selector(DreamderWindowController.closeCurrentTab(_:)))
            }
            .keymapShortcut(.closeTab)

            Button("Close Editor") {
                closeOrPerformClose(#selector(DreamderWindowController.closeActiveEditor(_:)))
            }
            .keymapShortcut(.closeEditor)

            Button("Close Window") {
                performCloseOnKeyWindow()
            }
            .keymapShortcut(.closeWindow)

            Button("Close Workspace") {
                performCloseOnKeyWindow()
            }
            .keymapShortcut(.closeWorkspace)
            .disabled(!(keyWindow()?.windowController is DreamderWindowController))
        }

        private func closeOrPerformClose(_ selector: Selector) {
            if let responder = responderForAction(selector) {
                NSApp.sendAction(selector, to: responder, from: nil)
            } else {
                performCloseOnKeyWindow()
            }
        }

        private func performCloseOnKeyWindow() {
            NSApp.sendAction(#selector(NSWindow.performClose(_:)), to: keyWindow(), from: nil)
        }
    }

    struct CloseTerminalButton: View {
        let utilityAreaViewModel: UtilityAreaViewModel?

        var body: some View {
            if let utilityAreaViewModel {
                Button("Close Terminal") {
                    utilityAreaViewModel.removeTerminals(utilityAreaViewModel.selectedTerminals)
                }
                .keymapShortcut(.closeTerminal)
            }
        }
    }

    struct WorkspaceButtons: View {
        let isWorkspaceSettingsEnabled: Bool
        var target: Any?

        var body: some View {
            Button("Workspace Settings") {
                NSApp.sendAction(#selector(DreamderWindowController.openWorkspaceSettings(_:)), to: target, from: nil)
            }
            .keymapShortcut(.workspaceSettings)
            .disabled(!isWorkspaceSettingsEnabled)

            Button("Trust Project\u{2026}") {
                NSApp.sendAction(#selector(DreamderWindowController.trustProject(_:)), to: target, from: nil)
            }
            .disabled(!isWorkspaceSettingsEnabled)

            Divider()

            Button("Save") {
                NSApp.sendAction(#selector(DreamderWindowController.saveDocument(_:)), to: target, from: nil)
            }
            .keymapShortcut(.save)
        }
    }
}
