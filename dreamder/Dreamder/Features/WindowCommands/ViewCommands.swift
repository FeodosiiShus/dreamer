//
//  ViewCommands.swift
//  Dreamder
//
//  Created by Wouter Hennen on 13/03/2023.
//

import SwiftUI

private let f12Key = KeyEquivalent("\u{F70F}")

struct ViewCommands: Commands {
    @AppSettings(\.textEditing.font.size)
    var editorFontSize
    @AppSettings(\.terminal.font.size)
    var terminalFontSize
    @AppSettings(\.general.dimEditorsWithoutFocus)
    var dimEditorsWithoutFocus

    @UpdatingWindowController var windowController: DreamderWindowController?

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            ToolWindowMenu()

            Menu("Editor Splits") {
                Button("Split Right") {
                    NSApp.sendAction(#selector(DreamderWindowController.splitEditorRight(_:)), to: nil, from: nil)
                }
                Button("Split Down") {
                    NSApp.sendAction(#selector(DreamderWindowController.splitEditorDown(_:)), to: nil, from: nil)
                }
                Divider()
                Button("Unsplit") {
                    NSApp.sendAction(#selector(DreamderWindowController.unsplitEditor(_:)), to: nil, from: nil)
                }
                Button("Unsplit All") {
                    NSApp.sendAction(#selector(DreamderWindowController.unsplitAllEditors(_:)), to: nil, from: nil)
                }
                Button("Change Splitter Orientation") {
                    NSApp.sendAction(
                        #selector(DreamderWindowController.changeEditorSplitterOrientation(_:)),
                        to: nil,
                        from: nil
                    )
                }
                Divider()
                Button("Go to Next Splitter") {
                    NSApp.sendAction(#selector(DreamderWindowController.gotoNextSplitter(_:)), to: nil, from: nil)
                }
                .keyboardShortcut(.tab, modifiers: [.option])
                Button("Go to Previous Splitter") {
                    NSApp.sendAction(#selector(DreamderWindowController.gotoPreviousSplitter(_:)), to: nil, from: nil)
                }
                .keyboardShortcut(.tab, modifiers: [.option, .shift])
            }
            .disabled(windowController == nil)

            Divider()

            Button("Show Command Palette") {
                NSApp.sendAction(#selector(DreamderWindowController.openCommandPalette(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("p", modifiers: [.shift, .command])

            Menu("Font Size") {
                Button("Increase") {
                    if editorFontSize < 288 {
                        editorFontSize += 1
                    }
                    if terminalFontSize < 288 {
                        terminalFontSize += 1
                    }
                }
                .keyboardShortcut("+")

                Button("Decrease") {
                    if editorFontSize > 1 {
                        editorFontSize -= 1
                    }
                    if terminalFontSize > 1 {
                        terminalFontSize -= 1
                    }
                }
                .keyboardShortcut("-")

                Divider()

                Button("Reset") {
                    editorFontSize = 12
                    terminalFontSize = 12
                }
                .keyboardShortcut("0", modifiers: [.command, .control])
            }
            .disabled(windowController == nil)

            Button("Customize Toolbar...") {

            }
            .disabled(true)

            Divider()

            HideCommands()

            Divider()

            Toggle("Dim editors without focus", isOn: $dimEditorsWithoutFocus)
        }
    }
}

extension ViewCommands {
    struct ToolWindowMenu: View {
        @UpdatingWindowController var windowController: DreamderWindowController?

        var body: some View {
            Menu("Tool Windows") {
                Button("Project") {
                    windowController?.toggleToolWindow(.project)
                }
                .keyboardShortcut("1", modifiers: [.command])

                Button("Commit") {
                    windowController?.toggleToolWindow(.commit)
                }
                .keyboardShortcut("0", modifiers: [.command])

                Button("Structure") {
                    windowController?.toggleToolWindow(.structure)
                }
                .keyboardShortcut("7", modifiers: [.command])

                Button("Find") {
                    windowController?.openSearchNavigator(nil)
                }
                .keyboardShortcut("3", modifiers: [.command])

                Button("Run") {
                    windowController?.toggleToolWindow(.run)
                }
                .keyboardShortcut("4", modifiers: [.command])

                Button("Problems") {
                    windowController?.toggleToolWindow(.problems)
                }
                .keyboardShortcut("6", modifiers: [.command])

                Button("Git") {
                    windowController?.toggleToolWindow(.git)
                }
                .keyboardShortcut("9", modifiers: [.command])

                Button("Language Services") {
                    windowController?.toggleToolWindow(.languageServices)
                }
                .keyboardShortcut("l", modifiers: [.control, .command])

                Button("Terminal") {
                    windowController?.toggleToolWindow(.terminal)
                }
                .keyboardShortcut(f12Key, modifiers: [.option])

                Divider()

                Button("Hide All Tool Windows") {
                    windowController?.hideAllToolWindows()
                }
                .keyboardShortcut(f12Key, modifiers: [.shift, .command])

                Button("Maximize Bottom Tool Window") {
                    windowController?.toggleBottomToolWindowMaximized()
                }
                .keyboardShortcut("\"", modifiers: [.shift, .command])
            }
            .disabled(windowController == nil)
        }
    }
}

extension ViewCommands {
    struct HideCommands: View {
        @UpdatingWindowController var windowController: DreamderWindowController?

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
            .keyboardShortcut("t", modifiers: [.option, .command])

            Button("\(isInterfaceHidden ? "Show" : "Hide") Interface") {
                windowController?.toggleInterface(shouldHide: !isInterfaceHidden)
            }
            .disabled(windowController == nil)
            .keyboardShortcut("H", modifiers: [.shift, .command])
        }
    }
}
