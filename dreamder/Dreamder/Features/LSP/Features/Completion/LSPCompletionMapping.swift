import CodeEditSourceEditor
import Foundation
import LanguageServerProtocol
import SwiftUI

struct LSPCompletionSuggestion: CodeSuggestionEntry {
    let label: String
    let detail: String?
    let documentation: String?
    let deprecated: Bool
    let kind: CompletionItemKind?
    let sortKey: String
    let filterKey: String
    let insertionText: String
    let replacementRange: LSPRange?

    var pathComponents: [String]? { nil }
    var targetPosition: CursorPosition? { nil }
    var sourcePreview: String? { nil }
    var image: Image { Image(LSPCompletionMapping.iconName(for: kind)) }
    var imageColor: SwiftUI.Color { .clear }

    init(item: CompletionItem) {
        self.label = item.label
        self.detail = item.detail
        self.documentation = LSPCompletionMapping.documentation(from: item.documentation)
        self.deprecated = item.deprecated ?? false
        self.kind = item.kind
        self.sortKey = item.sortText ?? item.label
        self.filterKey = item.filterText ?? item.label
        self.insertionText = LSPCompletionMapping.insertionText(for: item)
        self.replacementRange = LSPCompletionMapping.replacementRange(for: item)
    }
}

enum LSPCompletionMapping {
    static func suggestions(from items: [CompletionItem]) -> [LSPCompletionSuggestion] {
        items.map(LSPCompletionSuggestion.init(item:))
    }

    static func sorted(_ items: [CompletionItem]) -> [CompletionItem] {
        items.sorted { lhs, rhs in
            let leftKey = lhs.sortText ?? lhs.label
            let rightKey = rhs.sortText ?? rhs.label
            if leftKey != rightKey {
                return leftKey < rightKey
            }
            return lhs.label < rhs.label
        }
    }

    static func filtered(
        _ suggestions: [LSPCompletionSuggestion],
        prefix: String
    ) -> [LSPCompletionSuggestion] {
        guard !prefix.isEmpty else { return suggestions }
        let lowered = prefix.lowercased()
        return suggestions.filter { suggestion in
            suggestion.filterKey.lowercased().hasPrefix(lowered)
                || suggestion.label.lowercased().hasPrefix(lowered)
        }
    }

    static func insertionText(for item: CompletionItem) -> String {
        let text: String
        switch item.textEdit {
        case .some(.optionA(let edit)):
            text = edit.newText
        case .some(.optionB(let insertReplace)):
            text = insertReplace.newText
        case .none:
            text = item.insertText ?? item.label
        }
        return item.insertTextFormat == .snippet ? plainText(fromSnippet: text) : text
    }

    static func replacementRange(for item: CompletionItem) -> LSPRange? {
        switch item.textEdit {
        case .some(.optionA(let edit)):
            return edit.range
        case .some(.optionB(let insertReplace)):
            return insertReplace.insert
        case .none:
            return nil
        }
    }

    static func documentation(from documentation: TwoTypeOption<String, MarkupContent>?) -> String? {
        switch documentation {
        case .some(.optionA(let text)):
            return text
        case .some(.optionB(let content)):
            return content.value
        case .none:
            return nil
        }
    }

    static func iconName(for kind: CompletionItemKind?) -> String {
        switch kind {
        case .method:
            return "nodes/method"
        case .function:
            return "nodes/function"
        case .constructor:
            return "nodes/constructor"
        case .field:
            return "nodes/field"
        case .variable:
            return "nodes/variable"
        case .class:
            return "nodes/class"
        case .interface:
            return "nodes/interface"
        case .module, .unit:
            return "nodes/module"
        case .property:
            return "nodes/property"
        case .value:
            return "nodes/constant"
        case .enum:
            return "nodes/enum"
        case .keyword, .text:
            return "nodes/word"
        case .snippet:
            return "nodes/template"
        case .file:
            return "fileTypes/text"
        case .reference:
            return "nodes/related"
        case .folder:
            return "nodes/folder"
        case .enumMember, .constant:
            return "nodes/constant"
        case .struct:
            return "nodes/class"
        case .event:
            return "nodes/annotation"
        case .operator:
            return "nodes/methodReference"
        case .typeParameter:
            return "nodes/parameter"
        case .color:
            return "nodes/annotation"
        case .none:
            return "nodes/unknown"
        }
    }

    static func prefix(in text: String, before location: Int) -> String {
        let nsText = text as NSString
        guard location > 0, location <= nsText.length else { return "" }
        var start = location
        while start > 0 {
            guard let scalar = UnicodeScalar(nsText.character(at: start - 1)),
                  isIdentifierCharacter(scalar) else {
                break
            }
            start -= 1
        }
        return nsText.substring(with: NSRange(location: start, length: location - start))
    }

    static func triggerCharacter(in text: String, before location: Int) -> String? {
        let nsText = text as NSString
        guard location > 0, location <= nsText.length,
              let scalar = UnicodeScalar(nsText.character(at: location - 1)),
              !isIdentifierCharacter(scalar),
              !CharacterSet.whitespacesAndNewlines.contains(scalar) else {
            return nil
        }
        return String(Character(scalar))
    }

    private static func isIdentifierCharacter(_ scalar: UnicodeScalar) -> Bool {
        CharacterSet.alphanumerics.contains(scalar)
            || scalar == "_"
            || scalar == "$"
    }

    static func plainText(fromSnippet snippet: String) -> String {
        var result = ""
        var index = snippet.startIndex
        while index < snippet.endIndex {
            let character = snippet[index]
            if character == "\\", snippet.index(after: index) < snippet.endIndex {
                let next = snippet[snippet.index(after: index)]
                if next == "$" || next == "}" {
                    result.append(next)
                    index = snippet.index(index, offsetBy: 2)
                    continue
                }
            }
            guard character == "$" else {
                result.append(character)
                index = snippet.index(after: index)
                continue
            }
            let nextIndex = snippet.index(after: index)
            if nextIndex < snippet.endIndex, snippet[nextIndex] == "{" {
                guard let close = matchingBrace(in: snippet, from: nextIndex) else {
                    result.append(character)
                    index = nextIndex
                    continue
                }
                let content = snippet[snippet.index(after: nextIndex)..<close]
                if let colon = content.firstIndex(of: ":") {
                    result.append(plainText(fromSnippet: String(content[content.index(after: colon)...])))
                } else if let pipe = content.firstIndex(of: "|"), let last = content.lastIndex(of: "|"), pipe < last {
                    let choices = content[content.index(after: pipe)..<last]
                    result.append(choices.split(separator: ",").first.map(String.init) ?? "")
                }
                index = snippet.index(after: close)
                continue
            }
            if nextIndex < snippet.endIndex, snippet[nextIndex].isNumber {
                var cursor = nextIndex
                while cursor < snippet.endIndex, snippet[cursor].isNumber {
                    cursor = snippet.index(after: cursor)
                }
                index = cursor
                continue
            }
            result.append(character)
            index = nextIndex
        }
        return result
    }

    private static func matchingBrace(in text: String, from openIndex: String.Index) -> String.Index? {
        var depth = 0
        var index = openIndex
        while index < text.endIndex {
            switch text[index] {
            case "{":
                depth += 1
            case "}":
                depth -= 1
                if depth == 0 {
                    return index
                }
            default:
                break
            }
            index = text.index(after: index)
        }
        return nil
    }
}
