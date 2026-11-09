extension MarkdownMenuItem {
    var command: KeymapCommand {
        switch self {
        case .bold: .markdownBold
        case .italic: .markdownItalic
        case .strikethrough: .markdownStrikethrough
        case .codeSpan: .markdownCodeSpan
        case .createLink: .markdownCreateLink
        case .headerNormal: .markdownHeaderNormal
        case .headerTitle: .markdownHeaderTitle
        case .headerSubtitle: .markdownHeaderSubtitle
        case .heading3: .markdownHeading3
        case .heading4: .markdownHeading4
        case .heading5: .markdownHeading5
        case .heading6: .markdownHeading6
        case .headerUp: .markdownHeaderUp
        case .headerDown: .markdownHeaderDown
        case .insertTable: .markdownInsertTable
        case .formatTable: .markdownFormatTable
        case .generateTableOfContents: .markdownGenerateTableOfContents
        }
    }
}
