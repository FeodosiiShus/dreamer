import SwiftUI

struct MarkdownCommands: Commands {
    @UpdatingWindowController var windowController: DreamderWindowController?

    private var isMarkdownActive: Bool {
        windowController?.isActiveEditorMarkdown ?? false
    }

    private func shortcut(_ key: KeyEquivalent, _ modifiers: EventModifiers) -> KeyboardShortcut? {
        isMarkdownActive ? KeyboardShortcut(key, modifiers: modifiers) : nil
    }

    private func send(_ action: Selector) {
        NSApp.sendAction(action, to: nil, from: nil)
    }

    var body: some Commands {
        CommandMenu("Markdown") {
            Group {
                stylingItems
                Divider()
                Button("Create Link") {
                    send(#selector(DreamderWindowController.markdownCreateLink(_:)))
                }
                .keyboardShortcut(shortcut("u", [.shift, .command]))
                Divider()
                headerItems
                Divider()
                tableItems
                Divider()
                Button("Generate Table of Contents") {
                    send(#selector(DreamderWindowController.markdownGenerateTableOfContents(_:)))
                }
            }
            .disabled(!isMarkdownActive)
        }
    }

    @ViewBuilder private var stylingItems: some View {
        Button("Bold") {
            send(#selector(DreamderWindowController.markdownToggleBold(_:)))
        }
        .keyboardShortcut(shortcut("b", .command))
        Button("Italic") {
            send(#selector(DreamderWindowController.markdownToggleItalic(_:)))
        }
        .keyboardShortcut(shortcut("i", .command))
        Button("Strikethrough") {
            send(#selector(DreamderWindowController.markdownToggleStrikethrough(_:)))
        }
        .keyboardShortcut(shortcut("s", [.shift, .command]))
        Button("Code Span") {
            send(#selector(DreamderWindowController.markdownToggleCodeSpan(_:)))
        }
        .keyboardShortcut(shortcut("c", [.shift, .command]))
    }

    @ViewBuilder private var headerItems: some View {
        Menu("Header Level") {
            Button("Normal") {
                send(#selector(DreamderWindowController.markdownHeaderNormal(_:)))
            }
            Button("Title") {
                send(#selector(DreamderWindowController.markdownHeaderTitle(_:)))
            }
            Button("Subtitle") {
                send(#selector(DreamderWindowController.markdownHeaderSubtitle(_:)))
            }
            Button("Heading 3") {
                send(#selector(DreamderWindowController.markdownHeading3(_:)))
            }
            Button("Heading 4") {
                send(#selector(DreamderWindowController.markdownHeading4(_:)))
            }
            Button("Heading 5") {
                send(#selector(DreamderWindowController.markdownHeading5(_:)))
            }
            Button("Heading 6") {
                send(#selector(DreamderWindowController.markdownHeading6(_:)))
            }
        }
        Button("Header Up") {
            send(#selector(DreamderWindowController.markdownHeaderUp(_:)))
        }
        Button("Header Down") {
            send(#selector(DreamderWindowController.markdownHeaderDown(_:)))
        }
    }

    @ViewBuilder private var tableItems: some View {
        Button("Insert Table…") {
            send(#selector(DreamderWindowController.markdownInsertTable(_:)))
        }
        Button("Format Table") {
            send(#selector(DreamderWindowController.markdownFormatTable(_:)))
        }
    }
}
