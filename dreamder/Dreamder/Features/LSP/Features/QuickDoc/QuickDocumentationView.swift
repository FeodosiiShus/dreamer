import SwiftUI

struct QuickDocumentationView: View {
    @ObservedObject var model: QuickDocumentationViewModel

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(model.blocks.enumerated()), id: \.offset) { _, block in
                    blockView(block)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .glassPopup()
    }

    @ViewBuilder
    private func blockView(_ block: QuickDocumentationBlock) -> some View {
        switch block {
        case .prose(let markdown):
            Text(prose(markdown))
                .font(Islands.uiFont)
                .foregroundStyle(Islands.foreground)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .plain(let text):
            Text(text)
                .font(Islands.uiFont)
                .foregroundStyle(Islands.foreground)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .code(let text):
            Text(text)
                .font(Islands.codeFont)
                .foregroundStyle(Islands.foreground)
                .fixedSize(horizontal: true, vertical: true)
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Islands.controlRadius)
                        .fill(Islands.islandRaised)
                )
        }
    }

    private func prose(_ markdown: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        guard let attributed = try? AttributedString(markdown: markdown, options: options) else {
            return AttributedString(markdown)
        }
        return attributed
    }
}
