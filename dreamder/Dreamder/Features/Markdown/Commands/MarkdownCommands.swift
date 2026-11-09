import SwiftUI

enum MarkdownMenuItem: CaseIterable, Hashable {
    case bold
    case italic
    case strikethrough
    case codeSpan
    case createLink
    case headerNormal
    case headerTitle
    case headerSubtitle
    case heading3
    case heading4
    case heading5
    case heading6
    case headerUp
    case headerDown
    case insertTable
    case formatTable
    case generateTableOfContents

    static let styling: [MarkdownMenuItem] = [.bold, .italic, .strikethrough, .codeSpan]
    static let link: [MarkdownMenuItem] = [.createLink]
    static let headerLevels: [MarkdownMenuItem] = [
        .headerNormal, .headerTitle, .headerSubtitle, .heading3, .heading4, .heading5, .heading6
    ]
    static let headerSteps: [MarkdownMenuItem] = [.headerUp, .headerDown]
    static let table: [MarkdownMenuItem] = [.insertTable, .formatTable]
    static let tableOfContents: [MarkdownMenuItem] = [.generateTableOfContents]

    var title: String {
        switch self {
        case .bold: "Bold"
        case .italic: "Italic"
        case .strikethrough: "Strikethrough"
        case .codeSpan: "Code Span"
        case .createLink: "Create Link"
        case .headerNormal: "Normal"
        case .headerTitle: "Title"
        case .headerSubtitle: "Subtitle"
        case .heading3: "Heading 3"
        case .heading4: "Heading 4"
        case .heading5: "Heading 5"
        case .heading6: "Heading 6"
        case .headerUp: "Header Up"
        case .headerDown: "Header Down"
        case .insertTable: "Insert Table…"
        case .formatTable: "Format Table"
        case .generateTableOfContents: "Generate Table of Contents"
        }
    }

    var action: Selector {
        switch self {
        case .bold: #selector(DreamderWindowController.markdownToggleBold(_:))
        case .italic: #selector(DreamderWindowController.markdownToggleItalic(_:))
        case .strikethrough: #selector(DreamderWindowController.markdownToggleStrikethrough(_:))
        case .codeSpan: #selector(DreamderWindowController.markdownToggleCodeSpan(_:))
        case .createLink: #selector(DreamderWindowController.markdownCreateLink(_:))
        case .headerNormal: #selector(DreamderWindowController.markdownHeaderNormal(_:))
        case .headerTitle: #selector(DreamderWindowController.markdownHeaderTitle(_:))
        case .headerSubtitle: #selector(DreamderWindowController.markdownHeaderSubtitle(_:))
        case .heading3: #selector(DreamderWindowController.markdownHeading3(_:))
        case .heading4: #selector(DreamderWindowController.markdownHeading4(_:))
        case .heading5: #selector(DreamderWindowController.markdownHeading5(_:))
        case .heading6: #selector(DreamderWindowController.markdownHeading6(_:))
        case .headerUp: #selector(DreamderWindowController.markdownHeaderUp(_:))
        case .headerDown: #selector(DreamderWindowController.markdownHeaderDown(_:))
        case .insertTable: #selector(DreamderWindowController.markdownInsertTable(_:))
        case .formatTable: #selector(DreamderWindowController.markdownFormatTable(_:))
        case .generateTableOfContents: #selector(DreamderWindowController.markdownGenerateTableOfContents(_:))
        }
    }

    @discardableResult
    func send(to target: AnyObject? = nil) -> Bool {
        NSApp.sendAction(action, to: target, from: nil)
    }
}

struct MarkdownMenuButton: View {
    let item: MarkdownMenuItem
    let isActive: Bool
    var target: AnyObject?

    var body: some View {
        Button(item.title, action: perform)
            .keymapShortcut(item.command, when: isActive)
    }

    func perform() {
        item.send(to: target)
    }
}

struct MarkdownMenuContent: View {
    let isActive: Bool
    var target: AnyObject?

    var body: some View {
        Group {
            buttons(MarkdownMenuItem.styling)
            Divider()
            buttons(MarkdownMenuItem.link)
            Divider()
            Menu("Header Level") { buttons(MarkdownMenuItem.headerLevels) }
            buttons(MarkdownMenuItem.headerSteps)
            Divider()
            buttons(MarkdownMenuItem.table)
            Divider()
            buttons(MarkdownMenuItem.tableOfContents)
        }
        .disabled(!isActive)
    }

    private func buttons(_ items: [MarkdownMenuItem]) -> some View {
        ForEach(items, id: \.self) { MarkdownMenuButton(item: $0, isActive: isActive, target: target) }
    }
}

struct MarkdownCommands: Commands {
    @UpdatingWindowController var windowController: DreamderWindowController?

    var body: some Commands {
        CommandMenu("Markdown") {
            MarkdownMenuContent(isActive: windowController?.isActiveEditorMarkdown ?? false)
        }
    }
}
