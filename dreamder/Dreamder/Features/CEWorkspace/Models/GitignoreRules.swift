import Foundation

nonisolated struct GitignorePattern: Sendable, Equatable {
    enum Token: Sendable, Equatable {
        case literal(Unicode.Scalar)
        case anyCharacter
        case star
        case globstar
        case characterClass(CharacterClass)
        case never
    }

    struct CharacterClass: Sendable, Equatable {
        enum Item: Sendable, Equatable {
            case range(Unicode.Scalar, Unicode.Scalar)
            case named(String)
        }

        let isNegated: Bool
        let items: [Item]

        func matches(_ scalar: Unicode.Scalar) -> Bool {
            let matched = items.contains { item in
                switch item {
                case let .range(lower, upper):
                    scalar.value >= lower.value && scalar.value <= upper.value
                case .named(let name):
                    Self.scalar(scalar, isIn: name)
                }
            }
            return matched != isNegated
        }

        private static func scalar(_ scalar: Unicode.Scalar, isIn name: String) -> Bool {
            let properties = scalar.properties
            let isASCII = scalar.isASCII
            switch name {
            case "alnum": return isASCII && (properties.isAlphabetic || properties.numericType != nil)
            case "alpha": return isASCII && properties.isAlphabetic
            case "digit": return isASCII && properties.numericType != nil
            case "lower": return isASCII && properties.isLowercase
            case "upper": return isASCII && properties.isUppercase
            case "xdigit": return isASCII && properties.isASCIIHexDigit
            default: return controlOrPrintable(scalar, isIn: name)
            }
        }

        private static func controlOrPrintable(_ scalar: Unicode.Scalar, isIn name: String) -> Bool {
            let properties = scalar.properties
            switch name {
            case "blank": return scalar == " " || scalar == "\t"
            case "cntrl": return scalar.value < 0x20 || scalar.value == 0x7F
            case "graph": return scalar.value > 0x20 && scalar.value < 0x7F
            case "print": return scalar.value >= 0x20 && scalar.value < 0x7F
            case "punct":
                return scalar.value > 0x20 && scalar.value < 0x7F
                    && !(properties.isAlphabetic || properties.numericType != nil)
            case "space": return scalar == " " || (scalar.value >= 0x09 && scalar.value <= 0x0D)
            default: return false
            }
        }
    }

    let tokens: [Token]

    init(_ source: [Unicode.Scalar]) {
        var tokens: [Token] = []
        var index = 0
        while index < source.count {
            let scalar = source[index]
            switch scalar {
            case "\\":
                if index + 1 < source.count {
                    tokens.append(.literal(source[index + 1]))
                    index += 2
                } else {
                    tokens.append(.never)
                    index += 1
                }
            case "?":
                tokens.append(.anyCharacter)
                index += 1
            case "*":
                var end = index
                while end < source.count, source[end] == "*" { end += 1 }
                let startsSegment = index == 0 || source[index - 1] == "/"
                let endsSegment = end == source.count || source[end] == "/"
                tokens.append(end - index >= 2 && startsSegment && endsSegment ? .globstar : .star)
                index = end
            case "[":
                if let (characterClass, next) = Self.parseClass(source, from: index) {
                    tokens.append(.characterClass(characterClass))
                    index = next
                } else {
                    tokens.append(.never)
                    index = source.count
                }
            default:
                tokens.append(.literal(scalar))
                index += 1
            }
        }
        self.tokens = tokens
    }

    func matches(_ text: ArraySlice<Unicode.Scalar>) -> Bool {
        var matcher = Matcher(tokens: tokens, text: text)
        return matcher.match(tokenIndex: 0, textIndex: text.startIndex)
    }

    private static func parseClass(
        _ source: [Unicode.Scalar],
        from start: Int
    ) -> (CharacterClass, Int)? {
        var index = start + 1
        var isNegated = false
        if index < source.count, source[index] == "!" || source[index] == "^" {
            isNegated = true
            index += 1
        }
        var items: [CharacterClass.Item] = []
        var isFirst = true
        while index < source.count {
            let scalar = source[index]
            if scalar == "]" && !isFirst {
                return (CharacterClass(isNegated: isNegated, items: items), index + 1)
            }
            isFirst = false
            if scalar == "[", index + 1 < source.count, source[index + 1] == ":",
               let close = Self.namedClassEnd(source, from: index + 2) {
                let name = String(String.UnicodeScalarView(source[(index + 2)..<close]))
                items.append(.named(name))
                index = close + 2
                continue
            }
            var lower = scalar
            if scalar == "\\" {
                guard index + 1 < source.count else { return nil }
                index += 1
                lower = source[index]
            }
            index += 1
            if index + 1 < source.count, source[index] == "-", source[index + 1] != "]" {
                var upper = source[index + 1]
                index += 2
                if upper == "\\" {
                    guard index < source.count else { return nil }
                    upper = source[index]
                    index += 1
                }
                items.append(.range(lower, upper))
            } else {
                items.append(.range(lower, lower))
            }
        }
        return nil
    }

    private static func namedClassEnd(_ source: [Unicode.Scalar], from start: Int) -> Int? {
        var index = start
        while index + 1 < source.count {
            if source[index] == ":" && source[index + 1] == "]" { return index }
            index += 1
        }
        return nil
    }

    private struct Matcher {
        let tokens: [Token]
        let text: ArraySlice<Unicode.Scalar>
        var failed: Set<Int> = []

        init(tokens: [Token], text: ArraySlice<Unicode.Scalar>) {
            self.tokens = tokens
            self.text = text
        }

        mutating func match(tokenIndex: Int, textIndex: Int) -> Bool {
            let key = (textIndex - text.startIndex) * (tokens.count + 1) + tokenIndex
            if failed.contains(key) { return false }
            if run(tokenIndex: tokenIndex, textIndex: textIndex) { return true }
            failed.insert(key)
            return false
        }

        private mutating func run(tokenIndex start: Int, textIndex begin: Int) -> Bool {
            var tokenIndex = start
            var textIndex = begin
            while tokenIndex < tokens.count {
                switch tokens[tokenIndex] {
                case .literal(let expected):
                    guard textIndex < text.endIndex, text[textIndex] == expected else { return false }
                    tokenIndex += 1
                    textIndex += 1
                case .anyCharacter:
                    guard textIndex < text.endIndex, text[textIndex] != "/" else { return false }
                    tokenIndex += 1
                    textIndex += 1
                case .characterClass(let characterClass):
                    guard textIndex < text.endIndex, text[textIndex] != "/",
                          characterClass.matches(text[textIndex]) else { return false }
                    tokenIndex += 1
                    textIndex += 1
                case .never:
                    return false
                case .star:
                    return matchStar(rest: tokenIndex + 1, from: textIndex)
                case .globstar:
                    return matchGlobstar(rest: tokenIndex + 1, from: textIndex)
                }
            }
            return textIndex == text.endIndex
        }

        private mutating func matchStar(rest: Int, from start: Int) -> Bool {
            for position in start...text.endIndex {
                if rest == tokens.count {
                    if position == text.endIndex { return true }
                } else if match(tokenIndex: rest, textIndex: position) {
                    return true
                }
                if position < text.endIndex, text[position] == "/" { return false }
            }
            return false
        }

        private mutating func matchGlobstar(rest: Int, from start: Int) -> Bool {
            if rest == tokens.count { return true }
            if tokens[rest] == .literal("/"), match(tokenIndex: rest + 1, textIndex: start) {
                return true
            }
            var position = start
            while position <= text.endIndex {
                if match(tokenIndex: rest, textIndex: position) { return true }
                position += 1
            }
            return false
        }
    }
}

nonisolated struct GitignoreRule: Sendable, Equatable {
    let isNegated: Bool
    let isDirectoryOnly: Bool
    let isAnchored: Bool
    let pattern: GitignorePattern

    init?(line rawLine: Substring) {
        var scalars = Array(rawLine.unicodeScalars)
        if scalars.last == "\r" { scalars.removeLast() }
        guard let first = scalars.first, first != "#" else { return nil }
        scalars = Self.trimmingUnescapedTrailingSpaces(scalars)
        var isNegated = false
        if scalars.first == "!" {
            isNegated = true
            scalars.removeFirst()
        }
        var isDirectoryOnly = false
        if scalars.last == "/" {
            isDirectoryOnly = true
            scalars.removeLast()
        }
        guard !scalars.isEmpty else { return nil }
        let isAnchored = scalars.contains("/")
        if scalars.first == "/" { scalars.removeFirst() }
        guard !scalars.isEmpty else { return nil }
        self.isNegated = isNegated
        self.isDirectoryOnly = isDirectoryOnly
        self.isAnchored = isAnchored
        self.pattern = GitignorePattern(scalars)
    }

    func matches(
        relativePath: ArraySlice<Unicode.Scalar>,
        name: ArraySlice<Unicode.Scalar>,
        isDirectory: Bool
    ) -> Bool {
        guard isDirectory || !isDirectoryOnly else { return false }
        return pattern.matches(isAnchored ? relativePath : name)
    }

    private static func trimmingUnescapedTrailingSpaces(_ scalars: [Unicode.Scalar]) -> [Unicode.Scalar] {
        var end = 0
        var index = 0
        while index < scalars.count {
            if scalars[index] == "\\", index + 1 < scalars.count {
                index += 2
                end = index
            } else {
                index += 1
                if scalars[index - 1] != " " { end = index }
            }
        }
        return Array(scalars[0..<end])
    }
}

nonisolated struct GitignoreRuleSet: Sendable, Equatable {
    static let empty = GitignoreRuleSet(rules: [])

    let rules: [GitignoreRule]

    var isEmpty: Bool { rules.isEmpty }

    init(rules: [GitignoreRule]) {
        self.rules = rules
    }

    init(text: String) {
        self.init(rules: text.split(whereSeparator: \.isNewline).compactMap { GitignoreRule(line: $0) })
    }

    init(lines: [String]) {
        self.init(rules: lines.compactMap { GitignoreRule(line: Substring($0)) })
    }

    func verdict(
        relativePath: ArraySlice<Unicode.Scalar>,
        name: ArraySlice<Unicode.Scalar>,
        isDirectory: Bool
    ) -> Bool? {
        for rule in rules.reversed()
        where rule.matches(relativePath: relativePath, name: name, isDirectory: isDirectory) {
            return !rule.isNegated
        }
        return nil
    }

    func isIgnored(relativePath: String, isDirectory: Bool) -> Bool {
        guard !rules.isEmpty else { return false }
        let scalars = Array(relativePath.unicodeScalars)
        let nameStart = (scalars.lastIndex(of: "/") ?? -1) + 1
        return verdict(
            relativePath: ArraySlice(scalars),
            name: scalars[nameStart...],
            isDirectory: isDirectory
        ) ?? false
    }
}
