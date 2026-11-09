//
//  ViewCommands.swift
//  Dreamder
//
//  Created by Wouter Hennen on 13/03/2023.
//

import SwiftUI

struct ViewCommands: Commands {
    @AppSettings(\.general.dimEditorsWithoutFocus)
    var dimEditorsWithoutFocus

    @UpdatingWindowController var windowController: DreamderWindowController?

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            ToolWindowMenu()

            Menu("Editor Splits") {
                EditorSplitButtons()
            }
            .disabled(windowController == nil)

            Divider()

            CommandPaletteButton()

            Menu("Font Size") {
                FontSizeButtons()
            }
            .disabled(windowController == nil)

            Divider()

            HideCommands()

            Divider()

            Toggle("Dim editors without focus", isOn: $dimEditorsWithoutFocus)
                .keymapShortcut(.dimEditorsWithoutFocus)
        }
    }
}

extension ViewCommands {
    struct EditorSplitButtons: View {
        var target: Any?

        var body: some View {
            Button("Split Right") {
                send(#selector(DreamderWindowController.splitEditorRight(_:)))
            }
            .keymapShortcut(.splitRight)
            Button("Split Down") {
                send(#selector(DreamderWindowController.splitEditorDown(_:)))
            }
            .keymapShortcut(.splitDown)
            Divider()
            Button("Unsplit") {
                send(#selector(DreamderWindowController.unsplitEditor(_:)))
            }
            .keymapShortcut(.unsplit)
            Button("Unsplit All") {
                send(#selector(DreamderWindowController.unsplitAllEditors(_:)))
            }
            .keymapShortcut(.unsplitAll)
            Button("Change Splitter Orientation") {
                send(#selector(DreamderWindowController.changeEditorSplitterOrientation(_:)))
            }
            .keymapShortcut(.changeSplitterOrientation)
            Divider()
            Button("Go to Next Splitter") {
                send(#selector(DreamderWindowController.gotoNextSplitter(_:)))
            }
            .keymapShortcut(.gotoNextSplitter)
            Button("Go to Previous Splitter") {
                send(#selector(DreamderWindowController.gotoPreviousSplitter(_:)))
            }
            .keymapShortcut(.gotoPreviousSplitter)
        }

        private func send(_ selector: Selector) {
            NSApp.sendAction(selector, to: target, from: nil)
        }
    }

    struct CommandPaletteButton: View {
        var target: Any?

        var body: some View {
            Button("Show Command Palette") {
                NSApp.sendAction(#selector(DreamderWindowController.openCommandPalette(_:)), to: target, from: nil)
            }
            .keymapShortcut(.commandPalette)
        }
    }

    struct FontSizeButtons: View {
        @AppSettings(\.textEditing.font.size)
        var editorFontSize
        @AppSettings(\.terminal.font.size)
        var terminalFontSize

        var body: some View {
            Button("Increase") {
                if editorFontSize < 288 {
                    editorFontSize += 1
                }
                if terminalFontSize < 288 {
                    terminalFontSize += 1
                }
            }
            .keymapShortcut(.increaseFontSize)

            Button("Decrease") {
                if editorFontSize > 1 {
                    editorFontSize -= 1
                }
                if terminalFontSize > 1 {
                    terminalFontSize -= 1
                }
            }
            .keymapShortcut(.decreaseFontSize)

            Divider()

            Button("Reset") {
                editorFontSize = 12
                terminalFontSize = 12
            }
            .keymapShortcut(.resetFontSize)
        }
    }
}

extension ViewCommands {
    struct ToolWindowMenu: View {
        @UpdatingWindowController var windowController: DreamderWindowController?

        var body: some View {
            Menu("Tool Windows") {
                ToolWindowButtons(windowController: windowController)
            }
            .disabled(windowController == nil)
        }
    }

    struct ToolWindowButtons: View {
        let windowController: DreamderWindowController?

        var body: some View {
            Button("Project") {
                windowController?.toggleToolWindow(.project)
            }
            .keymapShortcut(.toolWindowProject)

            Button("Commit") {
                windowController?.toggleToolWindow(.commit)
            }
            .keymapShortcut(.toolWindowCommit)

            Button("Structure") {
                windowController?.toggleToolWindow(.structure)
            }
            .keymapShortcut(.toolWindowStructure)

            Button("Find") {
                windowController?.openSearchNavigator(nil)
            }
            .keymapShortcut(.toolWindowFind)

            Button("Run") {
                windowController?.toggleToolWindow(.run)
            }
            .keymapShortcut(.toolWindowRun)

            Button("Problems") {
                windowController?.toggleToolWindow(.problems)
            }
            .keymapShortcut(.toolWindowProblems)

            Button("Git") {
                windowController?.toggleToolWindow(.git)
            }
            .keymapShortcut(.toolWindowGit)

            Button("Language Services") {
                windowController?.toggleToolWindow(.languageServices)
            }
            .keymapShortcut(.toolWindowLanguageServices)

            Button("Terminal") {
                windowController?.toggleToolWindow(.terminal)
            }
            .keymapShortcut(.toolWindowTerminal)

            Divider()

            Button("Hide All Tool Windows") {
                windowController?.hideAllToolWindows()
            }
            .keymapShortcut(.hideAllToolWindows)

            Button("Maximize Bottom Tool Window") {
                windowController?.toggleBottomToolWindowMaximized()
            }
            .keymapShortcut(.maximizeBottomToolWindow)
        }
    }
}

extension ViewCommands {
    struct HideCommands: View {
        @UpdatingWindowController var windowController: DreamderWindowController?

        var body: some View {
            HideButtons(windowController: windowController)
        }
    }

    struct HideButtons: View {
        let windowController: DreamderWindowController?

        var toolbarCollapsed: Bool {
            windowController?.toolbarCollapsed ?? true
        }

        var isInterfaceHidden: Bool {
            return windowController?.isInterfaceStillHidden() ?? false
        }

        var body: some View {
            Button("\(toolbarCollapsed ? "Show" : "Hide") Toolbar") {
                windowController?.toggleToolbar()
            }
            .disabled(windowController == nil)
            .keymapShortcut(.toggleToolbar)

            Button("\(isInterfaceHidden ? "Show" : "Hide") Interface") {
                windowController?.toggleInterface(shouldHide: !isInterfaceHidden)
            }
            .disabled(windowController == nil)
            .keymapShortcut(.toggleInterface)
        }
    }
}
