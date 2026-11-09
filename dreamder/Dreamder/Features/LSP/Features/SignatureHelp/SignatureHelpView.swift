import SwiftUI

@MainActor
@Observable
final class SignatureHelpViewModel {
    private(set) var presentation: SignatureHelpPresentation

    init(presentation: SignatureHelpPresentation) {
        self.presentation = presentation
    }

    var rows: [SignatureHelpRow] {
        presentation.rows
    }

    var activeIndex: Int {
        presentation.activeIndex
    }

    var showsSwitchHint: Bool {
        presentation.rows.count > 1
    }

    func apply(_ presentation: SignatureHelpPresentation) {
        self.presentation = presentation
    }
}

@MainActor
enum SignatureHelpText {
    static func label(of row: SignatureHelpRow) -> AttributedString {
        var result = AttributedString()
        for segment in row.segments {
            var piece = AttributedString(segment.text)
            piece.font = segment.isActiveParameter ? Islands.codeFont.bold() : Islands.codeFont
            piece.foregroundColor = segment.isActiveParameter ? Islands.foreground : Islands.editorForeground
            result.append(piece)
        }
        return result
    }

    static func documentation(_ documentation: SignatureHelpDocumentation) -> AttributedString {
        guard documentation.isMarkdown,
              let attributed = try? AttributedString(
                markdown: documentation.text,
                options: AttributedString.MarkdownParsingOptions(
                    interpretedSyntax: .inlineOnlyPreservingWhitespace
                )
              ) else {
            return AttributedString(documentation.text)
        }
        return attributed
    }
}

struct SignatureHelpView: View {
    let model: SignatureHelpViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: SignatureHelpMetrics.rowSpacing) {
            ForEach(Array(model.rows.enumerated()), id: \.offset) { index, row in
                SignatureHelpRowView(row: row, isActive: model.showsSwitchHint && index == model.activeIndex)
            }
            if model.showsSwitchHint {
                Text("Switch with ↑ or ↓")
                    .font(Islands.smallFont)
                    .foregroundStyle(Islands.secondaryForeground)
                    .padding(.horizontal, SignatureHelpMetrics.rowInset)
            }
        }
        .padding(.horizontal, SignatureHelpMetrics.horizontalInset)
        .padding(.vertical, SignatureHelpMetrics.verticalInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassPopup()
    }
}

struct SignatureHelpRowView: View {
    let row: SignatureHelpRow
    let isActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: SignatureHelpMetrics.lineSpacing) {
            Text(SignatureHelpText.label(of: row))
                .lineLimit(1)
                .truncationMode(.tail)
            if let documentation = row.documentation {
                SignatureHelpDocumentationView(documentation: documentation)
            }
            if let documentation = row.parameterDocumentation {
                SignatureHelpDocumentationView(documentation: documentation)
            }
        }
        .padding(.horizontal, SignatureHelpMetrics.rowInset)
        .padding(.vertical, SignatureHelpMetrics.rowVerticalPadding / 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isActive ? Islands.actionHover : Color.clear,
            in: RoundedRectangle(cornerRadius: Islands.rowRadius)
        )
    }
}

struct SignatureHelpDocumentationView: View {
    let documentation: SignatureHelpDocumentation

    var body: some View {
        Text(SignatureHelpText.documentation(documentation))
            .font(Islands.smallFont)
            .foregroundStyle(Islands.secondaryForeground)
            .lineLimit(SignatureHelpMetrics.documentationLineLimit)
            .multilineTextAlignment(.leading)
    }
}
