import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

@Suite
struct StructureTreeCoverageTests {
    private func range(_ line: Int, _ character: Int, endLine: Int? = nil) -> LSPRange {
        LSPRange(
            start: Position(line: line, character: character),
            end: Position(line: endLine ?? line, character: character + 1)
        )
    }

    private func node(
        id: String,
        line: Int,
        start: Int? = nil,
        end: Int? = nil
    ) -> StructureNode {
        StructureNode(
            id: id,
            name: id,
            detail: nil,
            kind: .function,
            line: line,
            column: 1,
            children: [],
            rangeStartLine: start,
            rangeEndLine: end
        )
    }

    @Test
    func everyKindHasItsIntelliJIcon() {
        let expected: [StructureSymbolKind: String] = [
            .file: "nodes/unknown",
            .unknown: "nodes/unknown",
            .module: "nodes/module",
            .extensionDecl: "nodes/module",
            .namespace: "nodes/package",
            .package: "nodes/package",
            .classType: "nodes/class",
            .structType: "nodes/class",
            .actorType: "nodes/class",
            .enumType: "nodes/enum",
            .interface: "nodes/interface",
            .typeAlias: "nodes/type",
            .method: "nodes/method",
            .function: "nodes/function",
            .property: "nodes/property",
            .field: "nodes/field",
            .variable: "nodes/variable",
            .constant: "nodes/constant",
            .enumMember: "nodes/constant",
            .constructor: "nodes/constructor",
            .typeParameter: "nodes/parameter"
        ]
        #expect(Set(expected.keys) == Set(StructureSymbolKind.allCases))
        for kind in StructureSymbolKind.allCases {
            #expect(kind.iconName == expected[kind])
        }
    }

    @Test
    func everyLanguageServerSymbolKindMapsToAStructureKind() {
        let expected: [SymbolKind: StructureSymbolKind] = [
            .file: .file,
            .module: .module,
            .namespace: .namespace,
            .package: .package,
            .class: .classType,
            .method: .method,
            .property: .property,
            .field: .field,
            .constructor: .constructor,
            .enum: .enumType,
            .interface: .interface,
            .function: .function,
            .variable: .variable,
            .constant: .constant,
            .string: .field,
            .number: .field,
            .boolean: .field,
            .array: .field,
            .object: .field,
            .key: .field,
            .null: .field,
            .enumMember: .enumMember,
            .struct: .structType,
            .event: .function,
            .operator: .function,
            .typeParameter: .typeParameter
        ]
        #expect(Set(expected.keys) == Set(SymbolKind.allCases))
        for kind in SymbolKind.allCases {
            #expect(StructureSymbolKind(kind) == expected[kind])
        }
    }

    @Test
    func everySearchEverywhereKindMapsToAStructureKind() {
        let expected: [SearchEverywhereSymbolKind: StructureSymbolKind] = [
            .classType: .classType,
            .structType: .structType,
            .actorType: .actorType,
            .enumType: .enumType,
            .protocolType: .interface,
            .typeAlias: .typeAlias,
            .extensionDecl: .extensionDecl,
            .method: .method,
            .function: .function,
            .field: .field,
            .variable: .variable
        ]
        #expect(Set(expected.keys) == Set(SearchEverywhereSymbolKind.allCases))
        for kind in SearchEverywhereSymbolKind.allCases {
            #expect(StructureSymbolKind(kind) == expected[kind])
        }
    }

    @Test
    func containsUsesTheNodeLineWhenTheRangeStartIsMissing() {
        let withoutStart = node(id: "a", line: 2, start: nil, end: 5)
        #expect(withoutStart.contains(line: 2))
        #expect(withoutStart.contains(line: 5))
        #expect(withoutStart.contains(line: 1) == false)
        #expect(withoutStart.contains(line: 6) == false)

        let withStart = node(id: "b", line: 2, start: 1, end: 5)
        #expect(withStart.contains(line: 1))

        let withoutEnd = node(id: "c", line: 2)
        #expect(withoutEnd.contains(line: 2) == false)
    }

    @Test
    func rowsExposeTheNodeIdentity() {
        let row = StructureRow(node: node(id: "x", line: 1), depth: 3)
        #expect(row.id == "x")
        #expect(row.depth == 3)
    }

    @Test
    func documentSymbolResponseBuildsNestedNodes() throws {
        let response: DocumentSymbolResponse = .some(.optionA([
            DocumentSymbol(
                name: "Outer",
                detail: nil,
                kind: .class,
                range: range(0, 0, endLine: 9),
                selectionRange: range(0, 6),
                children: nil
            )
        ]))
        let nodes = try #require(StructureTreeBuilder.nodes(from: response))
        #expect(nodes.map(\.name) == ["Outer"])
        let outer = try #require(nodes.first)
        #expect(outer.rangeStartLine == 1)
        #expect(outer.rangeEndLine == 10)
        #expect(outer.id == "0")
    }

    @Test
    func symbolInformationResponseBuildsFlatNodesAndMarksDeprecatedOnes() throws {
        let location = Location(uri: "file:///a.swift", range: range(2, 4, endLine: 6))
        let response: DocumentSymbolResponse = .some(.optionB([
            SymbolInformation(name: "old", kind: .function, deprecated: true, location: location, containerName: "Box"),
            SymbolInformation(name: "fresh", kind: .method, deprecated: false, location: location, containerName: "Box"),
            SymbolInformation(name: "bare", kind: .variable, location: location)
        ]))
        let nodes = try #require(StructureTreeBuilder.nodes(from: response))
        #expect(nodes.map(\.name) == ["old", "fresh", "bare"])
        #expect(nodes.map(\.detail) == ["deprecated", "Box", nil])
        #expect(nodes.map(\.id) == ["0", "1", "2"])
        let old = try #require(nodes.first)
        #expect(old.rangeStartLine == 3)
        #expect(old.rangeEndLine == 7)
        #expect(old.line == 3)
        #expect(old.column == 5)
    }

    @Test
    func fallbackPrefersTheExtractorNestingLevelAndComputesRanges() throws {
        let text = "class A\nfunc b\nfunc c\n"
        let symbols = [
            ExtractedSymbol(name: "A", kind: .classType, line: 1, nestingLevel: 0),
            ExtractedSymbol(name: "b", kind: .method, line: 2, nestingLevel: 1),
            ExtractedSymbol(name: "c", kind: .method, line: 3, nestingLevel: 1)
        ]
        let nodes = StructureTreeBuilder.nodes(from: symbols, text: text)
        try #require(nodes.count == 1)
        let root = try #require(nodes.first)
        #expect(root.children.map(\.name) == ["b", "c"])
        #expect(root.rangeStartLine == 1)
        #expect(root.rangeEndLine == 4)
        #expect(root.children.map(\.rangeEndLine) == [2, 4])
        #expect(root.id == "fallback/0")
        #expect(root.column == 1)
        #expect(root.detail == nil)
    }

    @Test
    func fallbackHandlesWindowsLineEndingsAndOutOfRangeLines() throws {
        let text = "    x\r\ny\r\n"
        let symbols = [
            ExtractedSymbol(name: "x", kind: .variable, line: 1),
            ExtractedSymbol(name: "far", kind: .variable, line: 99),
            ExtractedSymbol(name: "before", kind: .variable, line: 0)
        ]
        let nodes = StructureTreeBuilder.nodes(from: symbols, text: text)
        #expect(nodes.map(\.name) == ["x", "far"])
        let first = try #require(nodes.first)
        let second = try #require(nodes.dropFirst().first)
        #expect(first.children.isEmpty)
        #expect(second.children.map(\.name) == ["before"])
    }

    @Test
    func fallbackOfEmptyTextIsEmpty() throws {
        #expect(StructureTreeBuilder.nodes(from: [], text: "").isEmpty)
        let nodes = StructureTreeBuilder.nodes(
            from: [ExtractedSymbol(name: "a", kind: .function, line: 1)],
            text: ""
        )
        #expect(nodes.map(\.name) == ["a"])
        #expect(try #require(nodes.first).rangeEndLine == 1)
    }

    @Test
    func fallbackNestsDeeperIndentationUnderThePreviousSymbol() throws {
        let text = "a\n  b\n    c\n  d\ne\n"
        let symbols = [
            ExtractedSymbol(name: "a", kind: .classType, line: 1),
            ExtractedSymbol(name: "b", kind: .classType, line: 2),
            ExtractedSymbol(name: "c", kind: .method, line: 3),
            ExtractedSymbol(name: "d", kind: .method, line: 4),
            ExtractedSymbol(name: "e", kind: .function, line: 5)
        ]
        let nodes = StructureTreeBuilder.nodes(from: symbols, text: text)
        #expect(nodes.map(\.name) == ["a", "e"])
        let top = try #require(nodes.first)
        #expect(top.children.map(\.name) == ["b", "d"])
        #expect(top.children.first?.children.map(\.name) == ["c"])
    }

    @Test
    func indentationStopsAtTheFirstNonWhitespaceCharacter() {
        #expect(StructureTreeBuilder.indentation(of: "") == 0)
        #expect(StructureTreeBuilder.indentation(of: "   ") == 3)
        #expect(StructureTreeBuilder.indentation(of: " \t") == 5)
        #expect(StructureTreeBuilder.indentation(of: "  x  ") == 2)
    }

    @Test
    func rowsHideChildrenOfCollapsedNodesOnly() {
        let leaf = node(id: "leaf", line: 3)
        let inner = StructureNode(
            id: "inner",
            name: "inner",
            detail: nil,
            kind: .classType,
            line: 2,
            column: 1,
            children: [leaf]
        )
        let outer = StructureNode(
            id: "outer",
            name: "outer",
            detail: nil,
            kind: .classType,
            line: 1,
            column: 1,
            children: [inner]
        )
        #expect(StructureTreeBuilder.rows(nodes: [outer], collapsed: []).map(\.node.id) == ["outer", "inner", "leaf"])
        #expect(StructureTreeBuilder.rows(nodes: [outer], collapsed: ["inner"]).map(\.node.id) == ["outer", "inner"])
        #expect(StructureTreeBuilder.rows(nodes: [outer], collapsed: ["outer"]).map(\.node.id) == ["outer"])
        #expect(StructureTreeBuilder.rows(nodes: [leaf], collapsed: ["leaf"]).map(\.node.id) == ["leaf"])
    }
}
