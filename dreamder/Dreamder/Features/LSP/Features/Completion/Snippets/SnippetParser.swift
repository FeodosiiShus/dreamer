import Foundation

nonisolated enum SnippetNode: Sendable, Equatable {
    case text(String)
    case tabStop(index: Int, children: [SnippetNode], choices: [String])
    case variable(name: String, children: [SnippetNode])
}

nonisolated struct SnippetParser {
    private let scalars: [Unicode.Scalar]
    private var position = 0

    static func parse(_ source: String) -> [SnippetNode] {
        var parser = SnippetParser(scalars: Array(source.unicodeScalars))
        return parser.parseNodes(insidePlaceholder: false)
    }

    private init(scalars: [Unicode.Scalar]) {
        self.scalars = scalars
    }

    private var current: Unicode.Scalar? {
        position < scalars.count ? scalars[position] : nil
    }

    private func scalarAt(_ offset: Int) -> Unicode.Scalar? {
        offset < scalars.count ? scalars[offset] : nil
    }

    private static func isDigit(_ scalar: Unicode.Scalar?) -> Bool {
        guard let scalar else { return false }
        return scalar.value >= 48 && scalar.value <= 57
    }

    private static func isIdentifierStart(_ scalar: Unicode.Scalar?) -> Bool {
        guard let scalar else { return false }
        return scalar == "_"
            || (scalar.value >= 65 && scalar.value <= 90)
            || (scalar.value >= 97 && scalar.value <= 122)
    }

    private static func isIdentifierPart(_ scalar: Unicode.Scalar?) -> Bool {
        isIdentifierStart(scalar) || isDigit(scalar)
    }

    private mutating func parseNodes(insidePlaceholder: Bool) -> [SnippetNode] {
        var nodes: [SnippetNode] = []
        var text = String.UnicodeScalarView()
        while let scalar = current {
            if scalar == "\\", let escaped = scalarAt(position + 1), "$}\\".unicodeScalars.contains(escaped) {
                text.append(escaped)
                position += 2
                continue
            }
            if scalar == "}" && insidePlaceholder {
                break
            }
            if scalar == "$", let node = parseDollar() {
                if !text.isEmpty {
                    nodes.append(.text(String(text)))
                    text = String.UnicodeScalarView()
                }
                nodes.append(node)
                continue
            }
            text.append(scalar)
            position += 1
        }
        if !text.isEmpty {
            nodes.append(.text(String(text)))
        }
        return nodes
    }

    private mutating func parseDollar() -> SnippetNode? {
        let start = position
        position += 1
        if let node = parseDollarBody() {
            return node
        }
        position = start
        return nil
    }

    private mutating func parseDollarBody() -> SnippetNode? {
        if Self.isDigit(current) {
            return parseInteger().map { SnippetNode.tabStop(index: $0, children: [], choices: []) }
        }
        if Self.isIdentifierStart(current) {
            return .variable(name: parseIdentifier(), children: [])
        }
        guard current == "{" else { return nil }
        position += 1
        if Self.isDigit(current) {
            return parseBracedTabStop()
        }
        if Self.isIdentifierStart(current) {
            return parseBracedVariable()
        }
        return nil
    }

    private mutating func parseInteger() -> Int? {
        var digits = ""
        while let scalar = current, Self.isDigit(scalar) {
            digits.unicodeScalars.append(scalar)
            position += 1
        }
        return Int(digits)
    }

    private mutating func parseIdentifier() -> String {
        var name = String.UnicodeScalarView()
        while let scalar = current, Self.isIdentifierPart(scalar) {
            name.append(scalar)
            position += 1
        }
        return String(name)
    }

    private mutating func parseBracedTabStop() -> SnippetNode? {
        guard let index = parseInteger() else { return nil }
        if current == "}" {
            position += 1
            return .tabStop(index: index, children: [], choices: [])
        }
        if current == ":" {
            position += 1
            let children = parseNodes(insidePlaceholder: true)
            guard current == "}" else { return nil }
            position += 1
            return .tabStop(index: index, children: children, choices: [])
        }
        if current == "|" {
            position += 1
            guard let choices = parseChoices() else { return nil }
            return .tabStop(index: index, children: [], choices: choices)
        }
        return nil
    }

    private mutating func parseBracedVariable() -> SnippetNode? {
        let name = parseIdentifier()
        if current == "}" {
            position += 1
            return .variable(name: name, children: [])
        }
        if current == ":" {
            position += 1
            let children = parseNodes(insidePlaceholder: true)
            guard current == "}" else { return nil }
            position += 1
            return .variable(name: name, children: children)
        }
        return nil
    }

    private mutating func parseChoices() -> [String]? {
        var choices: [String] = []
        var choice = String.UnicodeScalarView()
        while let scalar = current {
            if scalar == "\\", let escaped = scalarAt(position + 1), "$}\\,|".unicodeScalars.contains(escaped) {
                choice.append(escaped)
                position += 2
            } else if scalar == "," {
                choices.append(String(choice))
                choice = String.UnicodeScalarView()
                position += 1
            } else if scalar == "|" && scalarAt(position + 1) == "}" {
                choices.append(String(choice))
                position += 2
                return choices
            } else {
                choice.append(scalar)
                position += 1
            }
        }
        return nil
    }
}
