//
//  NavigateCommands.swift
//  Dreamder
//
//  Created by Wouter Hennen on 13/03/2023.
//

import SwiftUI

enum MenuResponderChain {
    static func send(_ selector: Selector) {
        NSApp.sendAction(selector, to: nil, from: nil)
    }
}

struct NavigateCommands: Commands {

    @UpdatingWindowController var windowController: DreamderWindowController?

    var body: some Commands {
        CommandMenu("Navigate") {
            NavigateMenu(windowController: windowController)
        }
    }
}

struct NavigateMenu: View {
    let windowController: DreamderWindowController?
    let sendAction: @MainActor (Selector) -> Void
    private var lspService: LSPService { .shared }

    init(
        windowController: DreamderWindowController?,
        sendAction: @escaping @MainActor (Selector) -> Void = MenuResponderChain.send
    ) {
        self.windowController = windowController
        self.sendAction = sendAction
    }

    private var editor: Editor? {
        windowController?.workspace?.editorManager?.activeEditor
    }

    var canNavigate: Bool {
        guard let url = editor?.selectedTab?.file.url else { return false }
        return lspService.languageClient(forDocument: url) != nil
    }

    var body: some View {
        Group {
            Button("Search Everywhere", action: searchEverywhere)
                .keymapShortcut(.searchEverywhere)

            Button("Go to Class…", action: goToClass)
                .keymapShortcut(.goToClass)

            Button("Go to File…", action: goToFile)
                .keymapShortcut(.goToFile)

            Button("Go to Symbol…", action: goToSymbol)
                .keymapShortcut(.goToSymbol)

            Button("Find Action…", action: findAction)
                .keymapShortcut(.findAction)

            Button("Recent Files", action: recentFiles)
                .keymapShortcut(.recentFiles)

            Divider()
        }
        Group {
            Button("Go to Declaration or Usages", action: goToDeclaration)
                .keymapShortcut(.goToDeclaration)
                .disabled(!canNavigate)

            Button("Go to Type Declaration", action: goToTypeDeclaration)
                .keymapShortcut(.goToTypeDeclaration)
                .disabled(!canNavigate)

            NavigationExtrasMenuItems(windowController: windowController, sendAction: sendAction)

            Button("Show Usages", action: showUsages)
                .keymapShortcut(.showUsages)
                .disabled(!canNavigate)

            Button("Find Usages", action: findUsages)
                .keymapShortcut(.findUsages)
                .disabled(!canNavigate)

            Divider()
        }
        Group {
            Button("Reveal in Project Navigator", action: revealInProjectNavigator)
                .keymapShortcut(.revealInProjectNavigator)


            Divider()

        }
        Group {
            Button("Show Previous Tab", action: showPreviousTab)
                .keymapShortcut(.previousTab)
                .disabled(editor?.tabs.count ?? 0 <= 1)  // Disable if there's one or no tabs

            Button("Show Next Tab", action: showNextTab)
                .keymapShortcut(.nextTab)
                .disabled(editor?.tabs.count ?? 0 <= 1)  // Disable if there's one or no tabs
        }
        Group {
            Divider()

            Button("Go Forward", action: goForward)
                .keymapShortcut(.goForward)
                .disabled(!EditorLocationHistoryCommands.canGoForward(workspace: windowController?.workspace))

            Button("Go Back", action: goBack)
                .keymapShortcut(.goBack)
                .disabled(!EditorLocationHistoryCommands.canGoBack(workspace: windowController?.workspace))
        }
        .disabled(editor == nil)
    }

    func searchEverywhere() {
        sendAction(#selector(DreamderWindowController.openSearchEverywhere(_:)))
    }

    func goToClass() {
        sendAction(#selector(DreamderWindowController.openSearchEverywhereClasses(_:)))
    }

    func goToFile() {
        sendAction(#selector(DreamderWindowController.openSearchEverywhereFiles(_:)))
    }

    func goToSymbol() {
        sendAction(#selector(DreamderWindowController.openSearchEverywhereSymbols(_:)))
    }

    func findAction() {
        sendAction(#selector(DreamderWindowController.openSearchEverywhereActions(_:)))
    }

    func recentFiles() {
        sendAction(#selector(DreamderWindowController.openRecentFiles(_:)))
    }

    func goToDeclaration() {
        LSPNavigationCommands.goToDefinition(workspace: windowController?.workspace, typeDeclaration: false)
    }

    func goToTypeDeclaration() {
        LSPNavigationCommands.goToDefinition(workspace: windowController?.workspace, typeDeclaration: true)
    }

    func showUsages() {
        sendAction(#selector(DreamderWindowController.showUsages(_:)))
    }

    func findUsages() {
        sendAction(#selector(DreamderWindowController.findUsages(_:)))
    }

    func revealInProjectNavigator() {
        sendAction(#selector(ProjectNavigatorViewController.revealFile(_:)))
    }

    func showPreviousTab() {
        editor?.selectPreviousTab()
    }

    func showNextTab() {
        editor?.selectNextTab()
    }

    func goForward() {
        EditorLocationHistoryCommands.goForward(workspace: windowController?.workspace)
    }

    func goBack() {
        EditorLocationHistoryCommands.goBack(workspace: windowController?.workspace)
    }
}
