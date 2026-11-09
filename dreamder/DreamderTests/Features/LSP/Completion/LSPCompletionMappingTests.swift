import AppKit
import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

@Suite("LSP completion mapping")
struct LSPCompletionMappingTests {
    static let expectedIcons: [(CompletionItemKind?, String)] = [
        (.text, "nodes/word"),
        (.method, "nodes/method"),
        (.function, "nodes/function"),
        (.constructor, "nodes/constructor"),
        (.field, "nodes/field"),
        (.variable, "nodes/variable"),
        (.class, "nodes/class"),
        (.interface, "nodes/interface"),
        (.module, "nodes/module"),
        (.property, "nodes/property"),
        (.unit, "nodes/attribute"),
        (.value, "nodes/constant"),
        (.enum, "nodes/enum"),
        (.keyword, "nodes/word"),
        (.snippet, "nodes/template"),
        (.color, "nodes/annotation"),
        (.file, "fileTypes/anyType"),
        (.reference, "nodes/related"),
        (.folder, "nodes/folder"),
        (.enumMember, "nodes/enum"),
        (.constant, "nodes/constant"),
        (.struct, "nodes/record"),
        (.event, "nodes/annotation"),
        (.operator, "nodes/methodReference"),
        (.typeParameter, "nodes/type"),
        (nil, "nodes/unknown")
    ]

    @Test func mapsEveryKindToAnIcon() {
        #expect(Self.expectedIcons.count == CompletionItemKind.allCases.count + 1)
        for (kind, name) in Self.expectedIcons {
            #expect(LSPCompletionMapping.iconName(for: kind) == name)
        }
    }

    @Test func everyMappedIconExistsInTheAssetCatalog() {
        for (_, name) in Self.expectedIcons {
            #expect(NSImage(named: name) != nil, "\(name)")
        }
    }

    @Test func extractsPrefixBeforeCursor() {
        let text = "let value = obj.pri"
        #expect(LSPCompletionMapping.prefix(in: text, before: (text as NSString).length) == "pri")
        #expect(LSPCompletionMapping.prefix(in: text, before: 3) == "let")
        #expect(LSPCompletionMapping.prefix(in: "abc def", before: 4) == "")
        #expect(LSPCompletionMapping.prefix(in: "abc", before: 0) == "")
        #expect(LSPCompletionMapping.prefix(in: "abc", before: 99) == "")
        #expect(LSPCompletionMapping.prefix(in: "$ref_1", before: 6) == "$ref_1")
    }

    @Test func extractsTriggerCharacter() {
        let text = "value = object."
        #expect(LSPCompletionMapping.triggerCharacter(in: text, before: (text as NSString).length) == ".")
        #expect(LSPCompletionMapping.triggerCharacter(in: "value = object", before: 14) == nil)
        #expect(LSPCompletionMapping.triggerCharacter(in: "value = ", before: 8) == nil)
        #expect(LSPCompletionMapping.triggerCharacter(in: "", before: 0) == nil)
        #expect(LSPCompletionMapping.triggerCharacter(in: "ab", before: 9) == nil)
    }

    @Test func filterPrefixesStayOnOneLine() {
        #expect(LSPCompletionMapping.filterPrefix(in: "let x = fo", from: 8, to: 10) == "fo")
        #expect(LSPCompletionMapping.filterPrefix(in: "let x = fo", from: 10, to: 10) == "")
        #expect(LSPCompletionMapping.filterPrefix(in: "a\nfo", from: 0, to: 4) == nil)
        #expect(LSPCompletionMapping.filterPrefix(in: "abc", from: 2, to: 1) == nil)
        #expect(LSPCompletionMapping.filterPrefix(in: "abc", from: -1, to: 1) == nil)
        #expect(LSPCompletionMapping.filterPrefix(in: "abc", from: 0, to: 9) == nil)
    }

    @Test func readsPlainAndMarkupDocumentation() {
        #expect(LSPCompletionMapping.documentation(from: .optionA("plain")) == "plain")
        #expect(
            LSPCompletionMapping.documentation(from: .optionB(MarkupContent(kind: .markdown, value: "**md**")))
                == "**md**"
        )
        #expect(LSPCompletionMapping.documentation(from: nil) == nil)
    }
}
