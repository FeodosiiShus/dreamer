import Foundation

nonisolated enum RegexReplacement {
    nonisolated struct TemplateError: Error, Equatable, Sendable {
        let message: String
    }

    nonisolated private struct Groups {
        let count: Int
        let numbered: [String?]
        let names: Set<String>
        let named: [String: String]

        func group(_ number: Int) throws -> String? {
            guard number >= 0, number <= count else { throw TemplateError(message: "No group \(number)") }
            return numbered[number]
        }

        func group(named name: String) throws -> String? {
            guard names.contains(name) else { throw TemplateError(message: "No group with name <\(name)>") }
            return named[name]
        }
    }

    nonisolated private struct ConversionRegion {
        let start: Int
        var end: Int
        var toUpperCase: Bool
    }

    nonisolated private struct Builder {
        let template: [Character]
        let groups: Groups
        var cursor = 0
        var replacement: [Character] = []
        var regions: [ConversionRegion] = []

        init(template: String, groups: Groups) {
            self.template = Array(template)
            self.groups = groups
        }

        mutating func build() throws -> String {
            while cursor < template.count {
                let character = template[cursor]
                cursor += 1
                switch character {
                case "\\":
                    try processEscapedCharacter()
                case "$":
                    try processGroupValue()
                default:
                    replacement.append(character)
                }
            }
            return generateResult()
        }

        private mutating func processEscapedCharacter() throws {
            guard cursor < template.count else {
                throw TemplateError(message: "character to be escaped is missing")
            }
            let character = template[cursor]
            cursor += 1
            switch character {
            case "n": replacement.append("\n")
            case "r": replacement.append("\r")
            case "b": replacement.append("\u{08}")
            case "t": replacement.append("\t")
            case "f": replacement.append("\u{0C}")
            case "x": processHexadecimalEscape()
            case "l": startConversionForCharacter(toUpperCase: false)
            case "u": startConversionForCharacter(toUpperCase: true)
            case "L": startConversionForRegion(toUpperCase: false)
            case "U": startConversionForRegion(toUpperCase: true)
            case "E": resetConversionState()
            default: replacement.append(character)
            }
        }

        private mutating func processHexadecimalEscape() {
            guard cursor + 4 <= template.count else { return }
            let digits = String(template[cursor..<cursor + 4])
            guard digits.allSatisfy(\.isHexDigit), let code = UInt32(digits, radix: 16) else { return }
            cursor += 4
            replacement.append(Unicode.Scalar(code).map { Character($0) } ?? "\u{FFFD}")
        }

        private mutating func processGroupValue() throws {
            guard cursor < template.count else {
                throw TemplateError(message: "Illegal group reference: group index is missing")
            }
            var character = template[cursor]
            cursor += 1
            let value: String?
            if character == "{" {
                var name = ""
                while cursor < template.count {
                    character = template[cursor]
                    if Self.isLatinLetter(character) || Self.isDigit(character) {
                        name.append(character)
                        cursor += 1
                    } else {
                        break
                    }
                }
                guard !name.isEmpty else {
                    throw TemplateError(message: "named capturing group has 0 length name")
                }
                guard character == "}" else {
                    throw TemplateError(message: "named capturing group is missing trailing '}'")
                }
                if let first = name.first, Self.isDigit(first) {
                    throw TemplateError(message: "capturing group name {\(name)} starts with digit character")
                }
                cursor += 1
                value = try groups.group(named: name)
            } else {
                guard let digit = Self.digitValue(character) else {
                    throw TemplateError(message: "Illegal group reference")
                }
                var reference = digit
                while cursor < template.count, let next = Self.digitValue(template[cursor]) {
                    let extended = reference * 10 + next
                    if groups.count < extended { break }
                    reference = extended
                    cursor += 1
                }
                value = try groups.group(reference)
            }
            if let value {
                replacement.append(contentsOf: value)
            }
        }

        private func generateResult() -> String {
            guard !regions.isEmpty else { return String(replacement) }
            var regions = regions
            let lastIndex = regions.count - 1
            if regions[lastIndex].end < 0 || regions[lastIndex].end > replacement.count {
                regions[lastIndex].end = replacement.count
            }
            var result = ""
            var currentOffset = 0
            for region in regions {
                let start = min(max(region.start, currentOffset), replacement.count)
                let end = min(max(region.end, start), replacement.count)
                result += String(replacement[currentOffset..<start])
                let converted = String(replacement[start..<end])
                result += region.toUpperCase ? converted.uppercased() : converted.lowercased()
                currentOffset = end
            }
            result += String(replacement[currentOffset...])
            return result
        }

        private mutating func startConversionForCharacter(toUpperCase: Bool) {
            let currentOffset = replacement.count
            if let last = regions.last, !(last.end >= 0 && last.end <= currentOffset) { return }
            regions.append(ConversionRegion(start: currentOffset, end: currentOffset + 1, toUpperCase: toUpperCase))
        }

        private mutating func startConversionForRegion(toUpperCase: Bool) {
            let currentOffset = replacement.count
            guard let lastIndex = regions.indices.last else {
                regions.append(ConversionRegion(start: currentOffset, end: -1, toUpperCase: toUpperCase))
                return
            }
            if regions[lastIndex].start == currentOffset {
                regions[lastIndex].end = -1
                regions[lastIndex].toUpperCase = toUpperCase
                return
            }
            if regions[lastIndex].end == -1 {
                if regions[lastIndex].toUpperCase == toUpperCase { return }
                regions[lastIndex].end = currentOffset
            }
            regions.append(ConversionRegion(start: currentOffset, end: -1, toUpperCase: toUpperCase))
        }

        private mutating func resetConversionState() {
            guard let lastIndex = regions.indices.last else { return }
            let currentOffset = replacement.count
            if regions[lastIndex].start >= currentOffset {
                regions.removeLast()
            } else if regions[lastIndex].end == -1 {
                regions[lastIndex].end = currentOffset
            }
        }

        private static func isLatinLetter(_ character: Character) -> Bool {
            character.isASCII && character.isLetter
        }

        private static func isDigit(_ character: Character) -> Bool {
            digitValue(character) != nil
        }

        private static func digitValue(_ character: Character) -> Int? {
            guard character.isASCII else { return nil }
            return character.wholeNumberValue
        }
    }

    static func validate(template: String, regex: NSRegularExpression) throws {
        let count = regex.numberOfCaptureGroups
        let names = Set(captureGroupNames(in: regex.pattern))
        let groups = Groups(
            count: count,
            numbered: Array(repeating: "", count: count + 1),
            names: names,
            named: Dictionary(uniqueKeysWithValues: names.map { ($0, "") })
        )
        var builder = Builder(template: template, groups: groups)
        _ = try builder.build()
    }

    static func createReplacement(
        template: String,
        match: NSTextCheckingResult,
        in text: NSString,
        regex: NSRegularExpression
    ) throws -> String {
        let count = min(regex.numberOfCaptureGroups, max(match.numberOfRanges - 1, 0))
        var numbered: [String?] = []
        numbered.reserveCapacity(count + 1)
        for index in 0...count {
            numbered.append(substring(of: match.range(at: index), in: text))
        }
        let names = Set(captureGroupNames(in: regex.pattern))
        var named: [String: String] = [:]
        for name in names {
            if let value = substring(of: match.range(withName: name), in: text) {
                named[name] = value
            }
        }
        var builder = Builder(
            template: template,
            groups: Groups(count: count, numbered: numbered, names: names, named: named)
        )
        return try builder.build()
    }

    static func captureGroupNames(in pattern: String) -> [String] {
        let characters = Array(pattern)
        var names: [String] = []
        var index = 0
        var classDepth = 0
        while index < characters.count {
            let character = characters[index]
            if character == "\\" {
                if index + 1 < characters.count, characters[index + 1] == "Q" {
                    index += 2
                    while index < characters.count {
                        if characters[index] == "\\", index + 1 < characters.count, characters[index + 1] == "E" {
                            index += 2
                            break
                        }
                        index += 1
                    }
                } else {
                    index += 2
                }
                continue
            }
            if character == "[" {
                classDepth += 1
            } else if character == "]" {
                classDepth = max(classDepth - 1, 0)
            } else if classDepth == 0, character == "(",
                      index + 3 < characters.count,
                      characters[index + 1] == "?",
                      characters[index + 2] == "<",
                      characters[index + 3].isASCII,
                      characters[index + 3].isLetter {
                var end = index + 3
                var name = ""
                while end < characters.count, characters[end].isASCII,
                      characters[end].isLetter || characters[end].isNumber {
                    name.append(characters[end])
                    end += 1
                }
                if end < characters.count, characters[end] == ">" {
                    names.append(name)
                    index = end
                }
            }
            index += 1
        }
        return names
    }

    private static func substring(of range: NSRange, in text: NSString) -> String? {
        guard range.location != NSNotFound, NSMaxRange(range) <= text.length else { return nil }
        return text.substring(with: range)
    }
}
