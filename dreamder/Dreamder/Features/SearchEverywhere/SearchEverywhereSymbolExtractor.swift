import Foundation

nonisolated enum SearchEverywhereSymbolKind: String, Hashable, CaseIterable, Sendable {
    case classType
    case structType
    case enumType
    case protocolType
    case actorType
    case typeAlias
    case extensionDecl
    case method
    case function
    case field
    case variable

    var iconName: String {
        switch self {
        case .classType, .structType, .actorType:
            return "nodes/class"
        case .enumType:
            return "nodes/enum"
        case .protocolType:
            return "nodes/interface"
        case .typeAlias:
            return "nodes/type"
        case .extensionDecl:
            return "nodes/module"
        case .method:
            return "nodes/method"
        case .function:
            return "nodes/function"
        case .field:
            return "nodes/field"
        case .variable:
            return "nodes/variable"
        }
    }

    var isType: Bool {
        switch self {
        case .classType, .structType, .enumType, .protocolType, .actorType, .typeAlias:
            return true
        default:
            return false
        }
    }
}

nonisolated struct ExtractedSymbol: Equatable, Sendable {
    let name: String
    let kind: SearchEverywhereSymbolKind
    let line: Int
    var nestingLevel: Int?
}

struct SearchEverywhereSymbol: Hashable {
    let name: String
    let kind: SearchEverywhereSymbolKind
    let url: URL
    let line: Int
}

nonisolated enum SymbolExtractor {
    static let textFileExtensions: Set<String> = [
        "swift", "ts", "tsx", "js", "jsx", "mjs", "cjs", "java", "kt", "kts",
        "py", "go", "rs"
    ]

    private static let reservedNames: Set<String> = [
        "func", "var", "let", "class", "struct", "enum", "protocol", "actor",
        "typealias", "extension", "init", "subscript", "static", "where", "return"
    ]

    static func symbols(in text: String, fileExtension: String) -> [ExtractedSymbol] {
        let lines = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).replacingOccurrences(of: "\r", with: "") }
        let ext = fileExtension.lowercased()

        switch ext {
        case "swift":
            return swiftSymbols(in: lines)
        case "ts", "tsx", "js", "jsx", "mjs", "cjs":
            return javaScriptSymbols(in: lines)
        case "java":
            return javaSymbols(in: lines)
        case "kt", "kts":
            return kotlinSymbols(in: lines)
        case "py":
            return pythonSymbols(in: lines)
        case "go":
            return goSymbols(in: lines)
        case "rs":
            return rustSymbols(in: lines)
        case "md", "markdown":
            return MarkdownHeaderOutline.entries(in: text).map {
                ExtractedSymbol(name: $0.title, kind: .field, line: $0.line, nestingLevel: $0.depth)
            }
        default:
            return []
        }
    }

    private static func swiftSymbols(in lines: [String]) -> [ExtractedSymbol] {
        let typeRegex = regex(
            "^[ \\t]*(?:@[A-Za-z_][\\w.]*(?:\\([^)\\n]*\\))?[ \\t]+)*"
            + "(?:(?:public|internal|package|private|fileprivate|open|final|indirect|nonisolated|distributed)[ \\t]+)*"
            + "(class|struct|enum|protocol|actor|typealias)[ \\t]+([A-Za-z_][A-Za-z0-9_]*)"
        )
        let funcRegex = regex(
            "^[ \\t]*(?:@[A-Za-z_][\\w.]*(?:\\([^)\\n]*\\))?[ \\t]+)*"
            + "(?:(?:public|internal|package|private|fileprivate|open|final|static|class|override|mutating|"
            + "nonisolated|dynamic|convenience|required)[ \\t]+)*func[ \\t]+([A-Za-z_][A-Za-z0-9_]*)"
        )
        let propertyRegex = regex(
            "^[ \\t]*(?:@[A-Za-z_][\\w.]*(?:\\([^)\\n]*\\))?[ \\t]+)*"
            + "(?:(?:public|internal|package|private|fileprivate|open|final|static|weak|unowned|lazy|"
            + "nonisolated|dynamic|override|class)[ \\t]+)*(var|let)[ \\t]+([A-Za-z_][A-Za-z0-9_]*)"
        )
        let extensionRegex = regex(
            "^[ \\t]*(?:@[A-Za-z_][\\w.]*[ \\t]+)*"
            + "(?:(?:public|internal|private|fileprivate)[ \\t]+)*extension[ \\t]+([A-Za-z_][A-Za-z0-9_.]*)"
        )

        var symbols: [ExtractedSymbol] = []
        for (index, line) in lines.enumerated() {
            guard !isComment(line) else { continue }
            let number = index + 1

            if let typeRegex,
               let match = firstMatch(typeRegex, in: line),
               let keyword = group(match, 1, in: line),
               let name = group(match, 2, in: line) {
                let kind: SearchEverywhereSymbolKind
                switch keyword {
                case "struct": kind = .structType
                case "enum": kind = .enumType
                case "protocol": kind = .protocolType
                case "actor": kind = .actorType
                case "typealias": kind = .typeAlias
                default: kind = .classType
                }
                append(name: name, kind: kind, line: number, to: &symbols)
            }

            if let funcRegex,
               let match = firstMatch(funcRegex, in: line),
               let name = group(match, 1, in: line) {
                append(name: name, kind: .method, line: number, to: &symbols)
            }

            if let propertyRegex,
               let match = firstMatch(propertyRegex, in: line),
               let name = group(match, 2, in: line),
               indentation(of: line) <= 4 {
                append(name: name, kind: .field, line: number, to: &symbols)
            }

            if let extensionRegex,
               let match = firstMatch(extensionRegex, in: line),
               let name = group(match, 1, in: line) {
                append(name: name, kind: .extensionDecl, line: number, to: &symbols)
            }
        }
        return symbols
    }

    private static func javaScriptSymbols(in lines: [String]) -> [ExtractedSymbol] {
        let declarationRegex = regex(
            "^[ \\t]*(?:export[ \\t]+)?(?:default[ \\t]+)?(?:declare[ \\t]+)?(?:abstract[ \\t]+)?"
            + "(class|interface|enum)[ \\t]+([A-Za-z_$][\\w$]*)"
        )
        let typeAliasRegex = regex(
            "^[ \\t]*(?:export[ \\t]+)?(?:declare[ \\t]+)?type[ \\t]+([A-Za-z_$][\\w$]*)[ \\t]*="
        )
        let functionRegex = regex(
            "^[ \\t]*(?:export[ \\t]+)?(?:default[ \\t]+)?(?:declare[ \\t]+)?(?:async[ \\t]+)?"
            + "function[ \\t]*\\*?[ \\t]*([A-Za-z_$][\\w$]*)"
        )
        let variableRegex = regex(
            "^[ \\t]*(?:export[ \\t]+)?(?:declare[ \\t]+)?(?:const|let|var)[ \\t]+([A-Za-z_$][\\w$]*)[ \\t]*[:=]"
        )

        var symbols: [ExtractedSymbol] = []
        for (index, line) in lines.enumerated() {
            guard !isComment(line) else { continue }
            let number = index + 1

            if let declarationRegex,
               let match = firstMatch(declarationRegex, in: line),
               let keyword = group(match, 1, in: line),
               let name = group(match, 2, in: line) {
                let kind: SearchEverywhereSymbolKind
                switch keyword {
                case "interface": kind = .protocolType
                case "enum": kind = .enumType
                default: kind = .classType
                }
                append(name: name, kind: kind, line: number, to: &symbols)
            }

            if let typeAliasRegex,
               let match = firstMatch(typeAliasRegex, in: line),
               let name = group(match, 1, in: line) {
                append(name: name, kind: .typeAlias, line: number, to: &symbols)
            }

            if let functionRegex,
               let match = firstMatch(functionRegex, in: line),
               let name = group(match, 1, in: line) {
                append(name: name, kind: .function, line: number, to: &symbols)
            }

            if let variableRegex,
               let match = firstMatch(variableRegex, in: line),
               let name = group(match, 1, in: line) {
                append(name: name, kind: .variable, line: number, to: &symbols)
            }
        }
        return symbols
    }

    private static func javaSymbols(in lines: [String]) -> [ExtractedSymbol] {
        let typeRegex = regex(
            "^[ \\t]*(?:@[\\w.]+(?:\\([^)]*\\))?[ \\t]+)*"
            + "(?:(?:public|private|protected|abstract|final|static|sealed|non-sealed|strictfp)[ \\t]+)*"
            + "(class|interface|enum|record)[ \\t]+([A-Za-z_][A-Za-z0-9_]*)"
        )

        var symbols: [ExtractedSymbol] = []
        for (index, line) in lines.enumerated() {
            guard !isComment(line), let typeRegex, let match = firstMatch(typeRegex, in: line) else { continue }
            guard let keyword = group(match, 1, in: line), let name = group(match, 2, in: line) else { continue }
            let kind: SearchEverywhereSymbolKind
            switch keyword {
            case "interface": kind = .protocolType
            case "enum": kind = .enumType
            default: kind = .classType
            }
            append(name: name, kind: kind, line: index + 1, to: &symbols)
        }
        return symbols
    }

    private static func kotlinSymbols(in lines: [String]) -> [ExtractedSymbol] {
        let typeRegex = regex(
            "^[ \\t]*(?:(?:public|private|protected|internal|abstract|final|open|sealed|data|annotation|"
            + "companion|inner|value|inline|enum|suspend)[ \\t]+)*(class|interface|object)[ \\t]+([A-Za-z_][\\w]*)"
        )
        let functionRegex = regex(
            "^[ \\t]*(?:(?:public|private|protected|internal|open|override|abstract|inline|suspend|"
            + "operator|infix|tailrec|external|expect|actual)[ \\t]+)*fun[ \\t]+(?:<[^>]+>[ \\t]+)?([A-Za-z_][\\w]*)"
        )

        var symbols: [ExtractedSymbol] = []
        for (index, line) in lines.enumerated() {
            guard !isComment(line) else { continue }
            if let typeRegex,
               let match = firstMatch(typeRegex, in: line),
               let keyword = group(match, 1, in: line),
               let name = group(match, 2, in: line) {
                append(name: name, kind: keyword == "interface" ? .protocolType : .classType, line: index + 1, to: &symbols)
            }
            if let functionRegex,
               let match = firstMatch(functionRegex, in: line),
               let name = group(match, 1, in: line) {
                append(name: name, kind: .function, line: index + 1, to: &symbols)
            }
        }
        return symbols
    }

    private static func pythonSymbols(in lines: [String]) -> [ExtractedSymbol] {
        let classRegex = regex("^([ \\t]*)class[ \\t]+([A-Za-z_][A-Za-z0-9_]*)")
        let defRegex = regex("^([ \\t]*)(?:async[ \\t]+)?def[ \\t]+([A-Za-z_][A-Za-z0-9_]*)")

        var symbols: [ExtractedSymbol] = []
        for (index, line) in lines.enumerated() {
            guard !isComment(line) else { continue }
            let number = index + 1

            if let classRegex,
               let match = firstMatch(classRegex, in: line),
               let name = group(match, 2, in: line) {
                append(name: name, kind: .classType, line: number, to: &symbols)
            }

            if let defRegex,
               let match = firstMatch(defRegex, in: line),
               let indent = group(match, 1, in: line),
               let name = group(match, 2, in: line) {
                append(name: name, kind: indent.isEmpty ? .function : .method, line: number, to: &symbols)
            }
        }
        return symbols
    }

    private static func goSymbols(in lines: [String]) -> [ExtractedSymbol] {
        let typeRegex = regex("^[ \\t]*type[ \\t]+([A-Za-z_][A-Za-z0-9_]*)[ \\t]+(struct|interface)\\b")
        let funcRegex = regex("^[ \\t]*func[ \\t]+(?:\\([^)]*\\)[ \\t]*)?([A-Za-z_][A-Za-z0-9_]*)")
        let methodRegex = regex("^[ \\t]*func[ \\t]+\\([^)]*\\)[ \\t]*([A-Za-z_][A-Za-z0-9_]*)")

        var symbols: [ExtractedSymbol] = []
        for (index, line) in lines.enumerated() {
            guard !isComment(line) else { continue }
            let number = index + 1

            if let typeRegex,
               let match = firstMatch(typeRegex, in: line),
               let name = group(match, 1, in: line),
               let keyword = group(match, 2, in: line) {
                append(name: name, kind: keyword == "interface" ? .protocolType : .classType, line: number, to: &symbols)
            }

            if let funcRegex,
               let match = firstMatch(funcRegex, in: line),
               let name = group(match, 1, in: line) {
                let isMethod = methodRegex.flatMap { firstMatch($0, in: line) } != nil
                append(name: name, kind: isMethod ? .method : .function, line: number, to: &symbols)
            }
        }
        return symbols
    }

    private static func rustSymbols(in lines: [String]) -> [ExtractedSymbol] {
        let typeRegex = regex(
            "^[ \\t]*(?:pub(?:\\([^)]*\\))?[ \\t]+)?(?:unsafe[ \\t]+)?(struct|enum|trait)[ \\t]+([A-Za-z_][A-Za-z0-9_]*)"
        )
        let functionRegex = regex(
            "^[ \\t]*(?:pub(?:\\([^)]*\\))?[ \\t]+)?(?:const[ \\t]+)?(?:unsafe[ \\t]+)?(?:async[ \\t]+)?"
            + "(?:extern[ \\t]+\"[^\"]*\"[ \\t]+)?fn[ \\t]+([A-Za-z_][A-Za-z0-9_]*)"
        )

        var symbols: [ExtractedSymbol] = []
        for (index, line) in lines.enumerated() {
            guard !isComment(line) else { continue }
            let number = index + 1

            if let typeRegex,
               let match = firstMatch(typeRegex, in: line),
               let keyword = group(match, 1, in: line),
               let name = group(match, 2, in: line) {
                let kind: SearchEverywhereSymbolKind
                switch keyword {
                case "enum": kind = .enumType
                case "trait": kind = .protocolType
                default: kind = .structType
                }
                append(name: name, kind: kind, line: number, to: &symbols)
            }

            if let functionRegex,
               let match = firstMatch(functionRegex, in: line),
               let name = group(match, 1, in: line) {
                append(name: name, kind: .function, line: number, to: &symbols)
            }
        }
        return symbols
    }

    private static func append(
        name: String,
        kind: SearchEverywhereSymbolKind,
        line: Int,
        to symbols: inout [ExtractedSymbol]
    ) {
        guard !name.isEmpty, !reservedNames.contains(name) else { return }
        symbols.append(ExtractedSymbol(name: name, kind: kind, line: line))
    }

    private static func isComment(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("//")
            || trimmed.hasPrefix("/*")
            || trimmed.hasPrefix("*")
            || trimmed.hasPrefix("#")
    }

    private static func indentation(of line: String) -> Int {
        var count = 0
        for character in line {
            if character == " " {
                count += 1
            } else if character == "\t" {
                count += 4
            } else {
                break
            }
        }
        return count
    }

    private static func regex(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern)
    }

    private static func firstMatch(_ regex: NSRegularExpression, in line: String) -> NSTextCheckingResult? {
        let range = NSRange(location: 0, length: (line as NSString).length)
        return regex.firstMatch(in: line, options: [], range: range)
    }

    private static func group(_ match: NSTextCheckingResult, _ index: Int, in line: String) -> String? {
        guard index < match.numberOfRanges else { return nil }
        let range = match.range(at: index)
        guard range.location != NSNotFound else { return nil }
        return (line as NSString).substring(with: range)
    }
}
