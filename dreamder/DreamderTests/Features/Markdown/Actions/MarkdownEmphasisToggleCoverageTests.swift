import Foundation
import Testing
@testable import Dreamder

struct MarkdownEmphasisToggleCoverage {
    private func toggled(_ kind: MarkdownEmphasisKind, _ markup: String) -> String? {
        let parsed = MarkdownActionCaretMarkup(markup)
        guard let result = MarkdownEmphasisToggle.toggle(kind, text: parsed.text, selections: parsed.selections) else {
            return nil
        }
        return MarkdownActionCaretMarkup.render(result.text, result.selections)
    }

    @Test
    func selectionStartingInsideTheOpeningMarkerCollapsesToTheContentStart() {
        #expect(toggled(.bold, "*<selection>*abc</selection>**") == "<selection>abc</selection>")
    }

    @Test
    func selectionEndingInsideTheClosingMarkerCollapsesToTheContentEnd() {
        #expect(toggled(.bold, "**<selection>abc*</selection>*") == "<selection>abc</selection>")
    }
}
