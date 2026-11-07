import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

@MainActor @Suite("LSP completion mapping")
struct LSPCompletionMappingTests {
    private func item(
        label: String,
        kind: CompletionItemKind? = .method,
        sortText: String? = nil,
        filterText: String? = nil,
        insertText: String? = nil,
        textEdit: TwoTypeOption<TextEdit, InsertReplaceEdit>? = nil,
        insertTextFormat: InsertTextFormat? = .plaintext,
        deprecated: Bool? = nil
    ) -> CompletionItem {
        CompletionItem(
            label: label,
            kind: kind,
            detail: "detail of \(label)",
            deprecated: deprecated,
            sortText: sortText,
            filterText: filterText,
            insertText: insertText,
            insertTextFormat: insertTextFormat,
            textEdit: textEdit
        )
    }

    private func suggestion(_ label: String, filterText: String? = nil, kind: CompletionItemKind? = .method) -> LSPCompletionSuggestion {
        LSPCompletionSuggestion(item: item(label: label, kind: kind, filterText: filterText))
    }

    @Test func sortsBySortTextThenLabel() {
        let sorted = LSPCompletionMapping.sorted([
            item(label: "zeta", sortText: "02"),
            item(label: "alpha", sortText: "01"),
            item(label: "beta", sortText: "01"),
            item(label: "fallback")
        ])
        #expect(sorted.map(\.label) == ["alpha", "beta", "zeta", "fallback"])
    }

    @Test func filtersByPrefix() {
        let suggestions = [
            suggestion("print"),
            suggestion("printf"),
            suggestion("Private"),
            suggestion("" , filterText: "preview")
        ]
        #expect(LSPCompletionMapping.filtered(suggestions, prefix: "pri").map(\.label) == ["print", "printf", "Private"])
        #expect(LSPCompletionMapping.filtered(suggestions, prefix: "PREV").map(\.label) == [""])
        #expect(LSPCompletionMapping.filtered(suggestions, prefix: "").count == 4)
        #expect(LSPCompletionMapping.filtered(suggestions, prefix: "xyz").isEmpty)
    }

    @Test func extractsPrefixBeforeCursor() {
        let text = "let value = obj.pri"
        #expect(LSPCompletionMapping.prefix(in: text, before: (text as NSString).length) == "pri")
        #expect(LSPCompletionMapping.prefix(in: text, before: 3) == "let")
        #expect(LSPCompletionMapping.prefix(in: "abc def", before: 4) == "")
        #expect(LSPCompletionMapping.prefix(in: "abc", before: 0) == "")
        #expect(LSPCompletionMapping.prefix(in: "abc", before: 99) == "")
    }

    @Test func extractsTriggerCharacter() {
        let text = "value = object."
        #expect(LSPCompletionMapping.triggerCharacter(in: text, before: (text as NSString).length) == ".")
        #expect(LSPCompletionMapping.triggerCharacter(in: "value = object", before: 14) == nil)
        #expect(LSPCompletionMapping.triggerCharacter(in: "value = ", before: 8) == nil)
    }

    @Test func insertionTextPrefersTextEdit() {
        let edit = TextEdit(
            range: LSPRange(start: Position(line: 1, character: 2), end: Position(line: 1, character: 5)),
            newText: "replacement"
        )
        let withEdit = item(label: "ignored", insertText: "ignored", textEdit: .optionA(edit))
        #expect(LSPCompletionMapping.insertionText(for: withEdit) == "replacement")
        #expect(LSPCompletionMapping.insertionText(for: item(label: "labelOnly")) == "labelOnly")
        #expect(LSPCompletionMapping.insertionText(for: item(label: "label", insertText: "inserted")) == "inserted")
    }

    @Test func replacementRangePrefersInsertRange() {
        let range = LSPRange(start: Position(line: 3, character: 1), end: Position(line: 3, character: 4))
        let replace = InsertReplaceEdit(newText: "value", insert: range, replace: range)
        #expect(LSPCompletionMapping.replacementRange(for: item(label: "x", textEdit: .optionB(replace))) == range)
        #expect(LSPCompletionMapping.replacementRange(for: item(label: "x")) == nil)
    }

    @Test func flattensSnippets() {
        #expect(LSPCompletionMapping.plainText(fromSnippet: "print(${1:value})") == "print(value)")
        #expect(LSPCompletionMapping.plainText(fromSnippet: "for ${1:item} in ${2:items} {\n\t$0\n}") == "for item in items {\n\t\n}")
        #expect(LSPCompletionMapping.plainText(fromSnippet: "let x = $1") == "let x = ")
        #expect(LSPCompletionMapping.plainText(fromSnippet: "${1|public,private|} func") == "public func")
        #expect(LSPCompletionMapping.plainText(fromSnippet: "cost: \\$5") == "cost: $5")
        #expect(LSPCompletionMapping.plainText(fromSnippet: "plain text") == "plain text")
    }

    @Test func mapsKindsToIcons() {
        #expect(LSPCompletionMapping.iconName(for: .method) == "nodes/method")
        #expect(LSPCompletionMapping.iconName(for: .function) == "nodes/function")
        #expect(LSPCompletionMapping.iconName(for: .class) == "nodes/class")
        #expect(LSPCompletionMapping.iconName(for: .interface) == "nodes/interface")
        #expect(LSPCompletionMapping.iconName(for: .property) == "nodes/property")
        #expect(LSPCompletionMapping.iconName(for: .variable) == "nodes/variable")
        #expect(LSPCompletionMapping.iconName(for: .enum) == "nodes/enum")
        #expect(LSPCompletionMapping.iconName(for: nil) == "nodes/unknown")
    }

    @Test func suggestionCarriesItemData() {
        let value = LSPCompletionSuggestion(item: item(label: "print", filterText: "pr", deprecated: true))
        #expect(value.label == "print")
        #expect(value.detail == "detail of print")
        #expect(value.deprecated)
        #expect(value.filterKey == "pr")
        #expect(value.sortKey == "print")
    }
}
