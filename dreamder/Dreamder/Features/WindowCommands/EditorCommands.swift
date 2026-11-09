//
//  EditorCommands.swift
//  Dreamder
//
//  Created by Bogdan Belogurov on 21/05/2025.
//

import SwiftUI
import CodeEditKit
import CodeEditTextView

struct EditorCommands: Commands {
    @UpdatingWindowController var windowController: DreamderWindowController?

    static func activeEditor(of windowController: DreamderWindowController?) -> Editor? {
        windowController?.workspace?.editorManager?.activeEditor
    }

    static func isEditorFocused(editor: Editor?, firstResponder: NSResponder?) -> Bool {
        editor?.selectedTab != nil && firstResponder is TextView
    }

    static func canNavigate(editor: Editor?, lspService: LSPService) -> Bool {
        guard let url = editor?.selectedTab?.file.url else { return false }
        return lspService.languageClient(forDocument: url) != nil
    }

    var body: some Commands {
        CommandMenu("Editor") {
            EditorMenu(windowController: windowController)
        }

        CommandGroup(after: .toolbar) {
            SoftWrapMenuItem(windowController: windowController)
        }
    }
}

extension EditorCommands {
    struct EditorMenu: View {
        let windowController: DreamderWindowController?
        @FirstResponder private var firstResponder
        private var lspService: LSPService { .shared }

        private var editor: Editor? {
            EditorCommands.activeEditor(of: windowController)
        }

        var isEditorFocused: Bool {
            EditorCommands.isEditorFocused(editor: editor, firstResponder: firstResponder)
        }

        func selectedTab() -> EditorInstance? {
            editor?.selectedTab
        }

        var body: some View {
            LineEditButtons(currentTab: selectedTab, isEnabled: isEditorFocused)

            Divider()

            Menu("Structure") {
                MoveLinesButtons(currentTab: selectedTab, isEnabled: isEditorFocused)
            }

            Divider()

            CommentButtons(currentTab: selectedTab, isEnabled: isEditorFocused)

            Divider()

            SelectionButtons(currentTab: selectedTab, isEnabled: isEditorFocused)

            Divider()

            IndentButtons(currentTab: selectedTab, isEnabled: isEditorFocused)

            Divider()

            GoToLineButton(currentTab: selectedTab, isEnabled: isEditorFocused)

            Divider()

            QuickDocumentationButtons(isEnabled: EditorCommands.canNavigate(editor: editor, lspService: lspService))
        }
    }

    struct SoftWrapMenuItem: View {
        let windowController: DreamderWindowController?

        private var editor: Editor? {
            EditorCommands.activeEditor(of: windowController)
        }

        func selectedTab() -> EditorInstance? {
            editor?.selectedTab
        }

        var body: some View {
            SoftWrapButton(currentTab: selectedTab, isEnabled: selectedTab() != nil)
        }
    }
}

extension EditorCommands {
    typealias CurrentTab = @MainActor () -> EditorInstance?

    struct LineEditButtons: View {
        let currentTab: CurrentTab
        var isEnabled = true

        var body: some View {
            Group {
                Button("Duplicate Line or Selection") {
                    currentTab()?.actions.duplicateLineOrSelection()
                }
                .keymapShortcut(.duplicateLine)

                Button("Delete Line") {
                    currentTab()?.actions.deleteLine()
                }
                .keymapShortcut(.deleteLine)

                Button("Join Lines") {
                    currentTab()?.actions.joinLines()
                }
                .keymapShortcut(.joinLines)
            }
            .disabled(!isEnabled)
        }
    }

    struct MoveLinesButtons: View {
        let currentTab: CurrentTab
        var isEnabled = true

        var body: some View {
            Group {
                Button("Move Line Up") {
                    currentTab()?.actions.moveLines(up: true)
                }
                .keymapShortcut(.moveLineUp)

                Button("Move Line Down") {
                    currentTab()?.actions.moveLines(up: false)
                }
                .keymapShortcut(.moveLineDown)
            }
            .disabled(!isEnabled)
        }
    }

    struct CommentButtons: View {
        let currentTab: CurrentTab
        var isEnabled = true
        var onUnsupported: (String) -> Void = { _ in NSSound.beep() }

        var body: some View {
            Group {
                Button("Comment with Line Comment") {
                    report(currentTab()?.actions.toggleLineComment())
                }
                .keymapShortcut(.commentLine)

                Button("Comment with Block Comment") {
                    report(currentTab()?.actions.toggleBlockComment())
                }
                .keymapShortcut(.commentBlock)
            }
            .disabled(!isEnabled)
        }

        private func report(_ outcome: EditorCommentOutcome?) {
            if case .unsupported(let reason)? = outcome {
                onUnsupported(reason)
            }
        }
    }

    struct SelectionButtons: View {
        let currentTab: CurrentTab
        var isEnabled = true

        var body: some View {
            Group {
                Button("Add Selection for Next Occurrence") {
                    currentTab()?.actions.selectNextOccurrence()
                }
                .keymapShortcut(.selectNextOccurrence)

                Button("Unselect Occurrence") {
                    currentTab()?.actions.unselectLastOccurrence()
                }
                .keymapShortcut(.unselectOccurrence)

                Button("Select All Occurrences") {
                    currentTab()?.actions.selectAllOccurrences()
                }
                .keymapShortcut(.selectAllOccurrences)

                Button("Clone Caret Above") {
                    currentTab()?.actions.cloneCaret(above: true)
                }
                .keymapShortcut(.cloneCaretAbove)

                Button("Clone Caret Below") {
                    currentTab()?.actions.cloneCaret(above: false)
                }
                .keymapShortcut(.cloneCaretBelow)
            }
            .disabled(!isEnabled)
        }
    }

    struct IndentButtons: View {
        let currentTab: CurrentTab
        var isEnabled = true

        var body: some View {
            Group {
                Button("Indent Selection") {
                    currentTab()?.actions.indentSelection()
                }
                .keymapShortcut(.indentSelection)

                Button("Unindent Selection") {
                    currentTab()?.actions.unindentSelection()
                }
                .keymapShortcut(.unindentSelection)
            }
            .disabled(!isEnabled)
        }
    }

    struct GoToLineButton: View {
        let currentTab: CurrentTab
        var isEnabled = true

        var body: some View {
            Button("Go to Line/Column…") {
                currentTab()?.actions.showGoToLine()
            }
            .keymapShortcut(.goToLine)
            .disabled(!isEnabled)
        }
    }

    struct SoftWrapButton: View {
        let currentTab: CurrentTab
        var isEnabled = true

        var body: some View {
            Button("Toggle Soft Wraps") {
                currentTab()?.toggleSoftWraps()
            }
            .keymapShortcut(.toggleSoftWraps)
            .disabled(!isEnabled)
        }
    }

    struct QuickDocumentationButtons: View {
        let isEnabled: Bool
        var target: Any?

        var body: some View {
            Button("Quick Documentation") {
                showQuickDocumentation()
            }
            .keymapShortcut(.quickDocumentation)
            .disabled(!isEnabled)

            Button("") {
                showQuickDocumentation()
            }
            .keymapShortcut(.quickDocumentation, at: 1)
            .disabled(!isEnabled)
        }

        private func showQuickDocumentation() {
            NSApp.sendAction(
                #selector(DreamderWindowController.showQuickDocumentation(_:)),
                to: target,
                from: nil
            )
        }
    }
}
