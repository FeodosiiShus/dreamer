//
//  EditorCommands.swift
//  Dreamder
//
//  Created by Bogdan Belogurov on 21/05/2025.
//

import SwiftUI
import CodeEditKit

private let f1Key = KeyEquivalent("\u{F704}")

struct EditorCommands: Commands {

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
        CommandMenu("Editor") {
            Menu("Structure") {
                Button("Move line up") {
                    editor?.selectedTab?.rangeTranslator.moveLinesUp()
                }
                .keyboardShortcut("[", modifiers: [.command, .option])

                Button("Move line down") {
                    editor?.selectedTab?.rangeTranslator.moveLinesDown()
                }
                .keyboardShortcut("]", modifiers: [.command, .option])
            }

            Button("Quick Documentation") {
                NSApp.sendAction(
                    #selector(DreamderWindowController.showQuickDocumentation(_:)),
                    to: nil,
                    from: nil
                )
            }
            .keyboardShortcut("j", modifiers: [.control])
            .disabled(!canNavigate)

            Button("") {
                NSApp.sendAction(
                    #selector(DreamderWindowController.showQuickDocumentation(_:)),
                    to: nil,
                    from: nil
                )
            }
            .keyboardShortcut(f1Key, modifiers: [])
            .disabled(!canNavigate)
        }
    }
}
