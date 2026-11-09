import Foundation
import LanguageServerProtocol

nonisolated enum LSPCompletionMapping {
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
        case .text, .keyword:
            return "nodes/word"
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
        case .module:
            return "nodes/module"
        case .property:
            return "nodes/property"
        case .unit:
            return "nodes/attribute"
        case .value, .constant:
            return "nodes/constant"
        case .enum, .enumMember:
            return "nodes/enum"
        case .snippet:
            return "nodes/template"
        case .color, .event:
            return "nodes/annotation"
        case .file:
            return "fileTypes/anyType"
        case .reference:
            return "nodes/related"
        case .folder:
            return "nodes/folder"
        case .struct:
            return "nodes/record"
        case .operator:
            return "nodes/methodReference"
        case .typeParameter:
            return "nodes/type"
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

    static func isIdentifierCharacter(_ scalar: UnicodeScalar) -> Bool {
        CharacterSet.alphanumerics.contains(scalar)
            || scalar == "_"
            || scalar == "$"
    }

    static func filterPrefix(in text: String, from start: Int, to location: Int) -> String? {
        let nsText = text as NSString
        guard start >= 0, start <= location, location <= nsText.length else { return nil }
        let prefix = nsText.substring(with: NSRange(location: start, length: location - start))
        return prefix.contains(where: \.isNewline) ? nil : prefix
    }
}
