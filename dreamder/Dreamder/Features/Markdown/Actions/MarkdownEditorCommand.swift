import Foundation

nonisolated enum MarkdownEditorCommand: Equatable, Sendable {
    case toggle(MarkdownEmphasisKind)
    case createLink
    case headerLevel(Int)
    case headerUp
    case headerDown
    case insertTable(contentRows: Int, columns: Int)
    case formatTable
    case generateTableOfContents
}

nonisolated struct MarkdownEditorEnvironment: Sendable {
    var emphasisStyle: MarkdownEmphasisStyle = .asterisks
    var tableStyle: MarkdownTableStyle = .aligned
    var tabSize = 4
    var indentSize = 4
    var clipboard: @Sendable () -> String? = { nil }
    var relativePathExists: @Sendable (String) -> Bool = { _ in false }
}

nonisolated enum MarkdownEditorCommandRunner {
    static func run(
        _ command: MarkdownEditorCommand,
        text: String,
        selections: [NSRange],
        environment: MarkdownEditorEnvironment = MarkdownEditorEnvironment()
    ) -> MarkdownActionResult? {
        switch command {
        case .toggle(let kind):
            return MarkdownEmphasisToggle.toggle(
                kind,
                text: text,
                selections: selections,
                style: environment.emphasisStyle
            )
        case .createLink:
            if MarkdownLinkCreation.canUnwrap(text: text, selections: selections) {
                return MarkdownLinkCreation.unwrap(text: text, selections: selections)
            }
            return MarkdownLinkCreation.wrapSelections(
                text: text,
                selections: selections,
                clipboard: environment.clipboard(),
                relativePathExists: environment.relativePathExists
            )
        case .headerLevel(let level):
            return MarkdownHeaderLevel.set(level: level, text: text, selections: selections)
        case .headerUp:
            return MarkdownHeaderLevel.headerUp(text: text, selections: selections)
        case .headerDown:
            return MarkdownHeaderLevel.headerDown(text: text, selections: selections)
        case .insertTable(let contentRows, let columns):
            guard let caret = selections.first?.location else { return nil }
            return MarkdownTable.insertEmptyTable(
                text: text,
                caret: caret,
                contentRows: contentRows,
                columns: columns,
                style: environment.tableStyle
            )
        case .formatTable:
            return MarkdownTable.format(
                text: text,
                selections: selections,
                style: environment.tableStyle,
                tabSize: environment.tabSize
            )
        case .generateTableOfContents:
            guard let caret = selections.first?.location else { return nil }
            return MarkdownTableOfContents.generate(text: text, caret: caret, indentSize: environment.indentSize)
        }
    }
}
