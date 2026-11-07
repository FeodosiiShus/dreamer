import Foundation
import LanguageServerProtocol

nonisolated enum StructureSymbolKind: String, Equatable, CaseIterable, Sendable {
    case file
    case module
    case namespace
    case package
    case classType
    case structType
    case actorType
    case enumType
    case interface
    case typeAlias
    case extensionDecl
    case method
    case function
    case property
    case field
    case variable
    case constant
    case enumMember
    case constructor
    case typeParameter
    case unknown

    var iconName: String {
        switch self {
        case .file, .unknown: "nodes/unknown"
        case .module, .extensionDecl: "nodes/module"
        case .namespace, .package: "nodes/package"
        case .classType, .structType, .actorType: "nodes/class"
        case .enumType: "nodes/enum"
        case .interface: "nodes/interface"
        case .typeAlias: "nodes/type"
        case .method: "nodes/method"
        case .function: "nodes/function"
        case .property: "nodes/property"
        case .field: "nodes/field"
        case .variable: "nodes/variable"
        case .constant, .enumMember: "nodes/constant"
        case .constructor: "nodes/constructor"
        case .typeParameter: "nodes/parameter"
        }
    }

    init(_ kind: SymbolKind) {
        switch kind {
        case .file: self = .file
        case .module: self = .module
        case .namespace: self = .namespace
        case .package: self = .package
        case .class: self = .classType
        case .struct: self = .structType
        case .enum: self = .enumType
        case .interface: self = .interface
        case .method: self = .method
        case .function: self = .function
        case .property: self = .property
        case .field: self = .field
        case .variable: self = .variable
        case .constant: self = .constant
        case .enumMember: self = .enumMember
        case .constructor: self = .constructor
        case .typeParameter: self = .typeParameter
        case .event, .operator: self = .function
        case .string, .number, .boolean, .array, .object, .key, .null: self = .field
        }
    }

    init(_ kind: SearchEverywhereSymbolKind) {
        switch kind {
        case .classType: self = .classType
        case .structType: self = .structType
        case .actorType: self = .actorType
        case .enumType: self = .enumType
        case .protocolType: self = .interface
        case .typeAlias: self = .typeAlias
        case .extensionDecl: self = .extensionDecl
        case .method: self = .method
        case .function: self = .function
        case .field: self = .field
        case .variable: self = .variable
        }
    }
}

nonisolated struct StructureNode: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let detail: String?
    let kind: StructureSymbolKind
    let line: Int
    let column: Int
    var children: [StructureNode]
    var rangeStartLine: Int?
    var rangeEndLine: Int?

    func contains(line target: Int) -> Bool {
        guard let rangeEndLine else { return false }
        return (rangeStartLine ?? line) <= target && target <= rangeEndLine
    }
}

nonisolated enum StructureBreadcrumbs {
    static func path(in nodes: [StructureNode], line: Int) -> [StructureNode] {
        var result: [StructureNode] = []
        var level = nodes
        while let match = level.last(where: { $0.contains(line: line) }) {
            result.append(match)
            level = match.children
        }
        return result
    }
}

nonisolated struct StructureRow: Identifiable, Equatable, Sendable {
    let node: StructureNode
    let depth: Int

    var id: String { node.id }
}

nonisolated enum StructureTreeBuilder {
    static func nodes(from documentSymbols: [DocumentSymbol]) -> [StructureNode] {
        documentSymbols.enumerated().map { node($0.element, path: "\($0.offset)") }
    }

    static func nodes(from symbolInformations: [SymbolInformation]) -> [StructureNode] {
        symbolInformations.enumerated().map { index, symbol in
            let detail = symbol.deprecated == true ? "deprecated" : symbol.containerName
            return StructureNode(
                id: "\(index)",
                name: symbol.name,
                detail: detail,
                kind: StructureSymbolKind(symbol.kind),
                line: symbol.location.range.start.line + 1,
                column: symbol.location.range.start.character + 1,
                children: [],
                rangeStartLine: symbol.location.range.start.line + 1,
                rangeEndLine: symbol.location.range.end.line + 1
            )
        }
    }

    static func nodes(from response: DocumentSymbolResponse) -> [StructureNode]? {
        switch response {
        case .optionA(let documentSymbols)?:
            nodes(from: documentSymbols)
        case .optionB(let symbolInformations)?:
            nodes(from: symbolInformations)
        case .none:
            nil
        }
    }

    static func nodes(from extracted: [ExtractedSymbol], text: String) -> [StructureNode] {
        let lines = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).replacingOccurrences(of: "\r", with: "") }
        let items: [IndentedSymbol] = extracted.enumerated().map { index, symbol in
            let lineIndex = min(max(symbol.line - 1, 0), max(lines.count - 1, 0))
            let textIndent = lines.indices.contains(lineIndex) ? indentation(of: lines[lineIndex]) : 0
            let indent = symbol.nestingLevel ?? textIndent
            return IndentedSymbol(
                indent: indent,
                node: StructureNode(
                    id: "fallback/\(index)",
                    name: symbol.name,
                    detail: nil,
                    kind: StructureSymbolKind(symbol.kind),
                    line: symbol.line,
                    column: 1,
                    children: []
                )
            )
        }
        let ranged = items.enumerated().map { offset, item in
            var node = item.node
            let next = items[(offset + 1)...].first { $0.indent <= item.indent }
            node.rangeStartLine = node.line
            node.rangeEndLine = max(node.line, (next?.node.line).map { $0 - 1 } ?? lines.count)
            return IndentedSymbol(indent: item.indent, node: node)
        }
        var index = 0
        return build(ranged, index: &index, parentIndent: -1)
    }

    static func rows(nodes: [StructureNode], collapsed: Set<String>) -> [StructureRow] {
        var result: [StructureRow] = []
        func append(_ nodes: [StructureNode], depth: Int) {
            for node in nodes {
                result.append(StructureRow(node: node, depth: depth))
                if !collapsed.contains(node.id), !node.children.isEmpty {
                    append(node.children, depth: depth + 1)
                }
            }
        }
        append(nodes, depth: 0)
        return result
    }

    static func indentation(of line: String) -> Int {
        var width = 0
        for character in line {
            switch character {
            case " ":
                width += 1
            case "\t":
                width += 4
            default:
                return width
            }
        }
        return width
    }

    private struct IndentedSymbol {
        let indent: Int
        let node: StructureNode
    }

    private static func build(
        _ items: [IndentedSymbol],
        index: inout Int,
        parentIndent: Int
    ) -> [StructureNode] {
        var result: [StructureNode] = []
        while index < items.count {
            let item = items[index]
            guard item.indent > parentIndent else { break }
            index += 1
            var node = item.node
            if index < items.count, items[index].indent > item.indent {
                node.children = build(items, index: &index, parentIndent: item.indent)
            }
            result.append(node)
        }
        return result
    }

    private static func node(_ symbol: DocumentSymbol, path: String) -> StructureNode {
        let children = (symbol.children ?? []).enumerated().map { offset, child in
            node(child, path: "\(path)/\(offset)")
        }
        return StructureNode(
            id: path,
            name: symbol.name,
            detail: symbol.detail,
            kind: StructureSymbolKind(symbol.kind),
            line: symbol.selectionRange.start.line + 1,
            column: symbol.selectionRange.start.character + 1,
            children: children,
            rangeStartLine: symbol.range.start.line + 1,
            rangeEndLine: symbol.range.end.line + 1
        )
    }
}
