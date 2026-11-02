//
//  NavigateCommands.swift
//  Dreamder
//
//  Created by Wouter Hennen on 13/03/2023.
//

import SwiftUI

private let f7Key = KeyEquivalent("\u{F70A}")

struct NavigateCommands: Commands {

    @UpdatingWindowController var windowController: DreamderWindowController?
    @Service private var lspService: LSPService

    private var editor: Editor? {
        windowController?.workspace?.editorManager?.activeEditor
    }

    private var canNavigate: Bool {
        guard let url = editor?.selectedTab?.file.url else { return false }
        return lspService.languageClient(forDocument: url) != nil
    }

    var body: some Commands {
        CommandMenu("Navigate") {
            Group {
                Button("Search Everywhere") {
                    NSApp.sendAction(#selector(DreamderWindowController.openSearchEverywhere(_:)), to: nil, from: nil)
                }

                Button("Go to Class…") {
                    NSApp.sendAction(
                        #selector(DreamderWindowController.openSearchEverywhereClasses(_:)),
                        to: nil,
                        from: nil
                    )
                }

                Button("Go to File…") {
                    NSApp.sendAction(
                        #selector(DreamderWindowController.openSearchEverywhereFiles(_:)),
                        to: nil,
                        from: nil
                    )
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                Button("Go to Symbol…") {
                    NSApp.sendAction(
                        #selector(DreamderWindowController.openSearchEverywhereSymbols(_:)),
                        to: nil,
                        from: nil
                    )
                }
                .keyboardShortcut("o", modifiers: [.option, .command])

                Button("Find Action…") {
                    NSApp.sendAction(
                        #selector(DreamderWindowController.openSearchEverywhereActions(_:)),
                        to: nil,
                        from: nil
                    )
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])

                Button("Recent Files") {
                    NSApp.sendAction(#selector(DreamderWindowController.openRecentFiles(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("e", modifiers: [.command])

                Divider()
            }
            Group {
                Button("Go to Declaration or Usages") {
                    LSPNavigationCommands.goToDefinition(
                        workspace: windowController?.workspace,
                        typeDeclaration: false
                    )
                }
                .keyboardShortcut("b", modifiers: [.command])
                .disabled(!canNavigate)

                Button("Go to Type Declaration") {
                    LSPNavigationCommands.goToDefinition(
                        workspace: windowController?.workspace,
                        typeDeclaration: true
                    )
                }
                .keyboardShortcut("b", modifiers: [.shift, .command])
                .disabled(!canNavigate)

                Button("Show Usages") {
                    NSApp.sendAction(#selector(DreamderWindowController.showUsages(_:)), to: nil, from: nil)
                }
                .keyboardShortcut(f7Key, modifiers: [.option, .command])
                .disabled(!canNavigate)

                Button("Find Usages") {
                    NSApp.sendAction(#selector(DreamderWindowController.findUsages(_:)), to: nil, from: nil)
                }
                .keyboardShortcut(f7Key, modifiers: [.option])
                .disabled(!canNavigate)

                Divider()
            }
            Group {
                Button("Reveal in Project Navigator") {
                    NSApp.sendAction(#selector(ProjectNavigatorViewController.revealFile(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("j", modifiers: [.shift, .command])


                Divider()

            }
            Group {
                Button("Show Previous Tab") {
                    editor?.selectPreviousTab()
                }
                .keyboardShortcut("{", modifiers: [.command])
                .disabled(editor?.tabs.count ?? 0 <= 1)  // Disable if there's one or no tabs

                Button("Show Next Tab") {
                    editor?.selectNextTab()
                }
                .keyboardShortcut("}", modifiers: [.command])
                .disabled(editor?.tabs.count ?? 0 <= 1)  // Disable if there's one or no tabs
            }
            Group {
                Divider()

                Button("Go Forward") {
                    editor?.goForwardInHistory()
                }
                .disabled(!(editor?.canGoForwardInHistory ?? false))

                Button("Go Back") {
                    editor?.goBackInHistory()
                }
                .disabled(!(editor?.canGoBackInHistory ?? false))
            }
            .disabled(editor == nil)
        }
    }
}
