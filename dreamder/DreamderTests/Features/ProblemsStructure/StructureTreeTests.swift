import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

@Suite
struct StructureTreeTests {
    private func range(_ line: Int, _ character: Int) -> LSPRange {
        LSPRange(start: Position(line: line, character: character), end: Position(line: line, character: character + 1))
    }

    @Test
    func documentSymbolsNestAndBecomeOneBased() {
        let symbols = [
            DocumentSymbol(
                name: "Outer",
                detail: "struct",
                kind: .struct,
                range: range(0, 0),
                selectionRange: range(0, 7),
                children: [
                    DocumentSymbol(
                        name: "inner",
                        detail: nil,
                        kind: .method,
                        range: range(2, 4),
                        selectionRange: range(2, 8),
                        children: nil
                    )
                ]
            )
        ]
        let nodes = StructureTreeBuilder.nodes(from: symbols)
        #expect(nodes.count == 1)
        let outer = nodes[0]
        #expect(outer.name == "Outer")
        #expect(outer.kind == .structType)
        #expect(outer.line == 1)
        #expect(outer.column == 8)
        #expect(outer.children.count == 1)
        #expect(outer.children[0].name == "inner")
        #expect(outer.children[0].kind == .method)
        #expect(outer.children[0].line == 3)
        #expect(outer.children[0].column == 9)
        #expect(outer.children[0].id != outer.id)
    }

    @Test
    func symbolInformationStaysFlat() {
        let symbols = [
            SymbolInformation(
                name: "load",
                kind: .function,
                location: Location(uri: "file:///a.swift", range: range(4, 2)),
                containerName: "Store"
            )
        ]
        let nodes = StructureTreeBuilder.nodes(from: symbols)
        #expect(nodes.count == 1)
        #expect(nodes[0].name == "load")
        #expect(nodes[0].detail == "Store")
        #expect(nodes[0].line == 5)
        #expect(nodes[0].column == 3)
        #expect(nodes[0].children.isEmpty)
    }

    @Test
    func missingResponseProducesNil() {
        #expect(StructureTreeBuilder.nodes(from: nil) == nil)
    }

    @Test
    func fallbackNestsByIndentation() {
        let text = """
        struct Outer {
            func inner() {
                let nested = 1
            }
            let value = 1
        }
        """
        let nodes = StructureTreeBuilder.nodes(
            from: SymbolExtractor.symbols(in: text, fileExtension: "swift"),
            text: text
        )
        #expect(nodes.count == 1)
        #expect(nodes[0].name == "Outer")
        #expect(nodes[0].children.map(\.name) == ["inner", "value"])
        #expect(nodes[0].children[0].children.isEmpty)
    }

    @Test
    func fallbackKeepsSiblingsAtTopLevel() {
        let text = """
        func first() {}
        func second() {}
        """
        let nodes = StructureTreeBuilder.nodes(
            from: SymbolExtractor.symbols(in: text, fileExtension: "swift"),
            text: text
        )
        #expect(nodes.map(\.name) == ["first", "second"])
        #expect(nodes.allSatisfy { $0.children.isEmpty })
    }

    @Test
    func indentationCountsTabsAsFourSpaces() {
        #expect(StructureTreeBuilder.indentation(of: "    func a()") == 4)
        #expect(StructureTreeBuilder.indentation(of: "\tfunc a()") == 4)
        #expect(StructureTreeBuilder.indentation(of: "\t\tfunc a()") == 8)
        #expect(StructureTreeBuilder.indentation(of: "func a()") == 0)
    }

    @Test
    func rowsFlattenChildrenAndRespectCollapsedNodes() {
        let child = StructureNode(
            id: "1/0",
            name: "inner",
            detail: nil,
            kind: .method,
            line: 3,
            column: 9,
            children: []
        )
        let root = StructureNode(
            id: "1",
            name: "Outer",
            detail: nil,
            kind: .structType,
            line: 1,
            column: 8,
            children: [child]
        )
        let expanded = StructureTreeBuilder.rows(nodes: [root], collapsed: [])
        #expect(expanded.map(\.node.name) == ["Outer", "inner"])
        #expect(expanded.map(\.depth) == [0, 1])

        let collapsed = StructureTreeBuilder.rows(nodes: [root], collapsed: ["1"])
        #expect(collapsed.map(\.node.name) == ["Outer"])
    }

    @Test
    func kindsMapToIntelliJIcons() {
        #expect(StructureSymbolKind(SymbolKind.class).iconName == "nodes/class")
        #expect(StructureSymbolKind(SymbolKind.struct).iconName == "nodes/class")
        #expect(StructureSymbolKind(SymbolKind.enum).iconName == "nodes/enum")
        #expect(StructureSymbolKind(SymbolKind.interface).iconName == "nodes/interface")
        #expect(StructureSymbolKind(SymbolKind.method).iconName == "nodes/method")
        #expect(StructureSymbolKind(SymbolKind.function).iconName == "nodes/function")
        #expect(StructureSymbolKind(SymbolKind.field).iconName == "nodes/field")
        #expect(StructureSymbolKind(SymbolKind.variable).iconName == "nodes/variable")
        #expect(StructureSymbolKind(SymbolKind.constant).iconName == "nodes/constant")
        #expect(StructureSymbolKind(SymbolKind.property).iconName == "nodes/property")
        #expect(StructureSymbolKind(SymbolKind.constructor).iconName == "nodes/constructor")
        #expect(StructureSymbolKind(SymbolKind.typeParameter).iconName == "nodes/parameter")
        #expect(StructureSymbolKind(SymbolKind.file).iconName == "nodes/unknown")
        #expect(StructureSymbolKind(SearchEverywhereSymbolKind.extensionDecl).iconName == "nodes/module")
        #expect(StructureSymbolKind(SearchEverywhereSymbolKind.protocolType).iconName == "nodes/interface")
    }
}
