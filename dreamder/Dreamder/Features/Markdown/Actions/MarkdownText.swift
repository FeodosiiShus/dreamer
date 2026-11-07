import Foundation

nonisolated struct MarkdownText: Sendable, Equatable {
    struct Line: Sendable, Equatable {
        let start: Int
        let contentEnd: Int
        let end: Int

        var contentRange: Range<Int> { start..<contentEnd }
        var fullRange: Range<Int> { start..<end }
    }

    let units: [UInt16]
    let lines: [Line]

    init(_ string: String) {
        self.init(units: Array(string.utf16))
    }

    init(units: [UInt16]) {
        self.units = units
        var lines: [Line] = []
        var start = 0
        var index = 0
        while index < units.count {
            let unit = units[index]
            if unit == Self.lineFeed {
                lines.append(Line(start: start, contentEnd: index, end: index + 1))
                index += 1
                start = index
            } else if unit == Self.carriageReturn {
                let next = index + 1
                if next < units.count, units[next] == Self.lineFeed {
                    lines.append(Line(start: start, contentEnd: index, end: index + 2))
                    index += 2
                } else {
                    lines.append(Line(start: start, contentEnd: index, end: index + 1))
                    index += 1
                }
                start = index
            } else {
                index += 1
            }
        }
        lines.append(Line(start: start, contentEnd: units.count, end: units.count))
        self.lines = lines
    }

    var length: Int { units.count }

    var string: String { String(decoding: units, as: UTF16.self) }

    func lineIndex(containing offset: Int) -> Int {
        var low = 0
        var high = lines.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if lines[middle].start <= offset {
                low = middle
            } else {
                high = middle - 1
            }
        }
        return low
    }

    func string(_ range: Range<Int>) -> String {
        String(decoding: units[range], as: UTF16.self)
    }

    func string(_ range: NSRange) -> String {
        string(range.location..<(range.location + range.length))
    }

    func isBlank(_ range: Range<Int>) -> Bool {
        units[range].allSatisfy { Self.isSpaceOrTab($0) }
    }

    func isBlankLine(_ index: Int) -> Bool {
        isBlank(lines[index].contentRange)
    }

    func firstIndex(of unit: UInt16, in range: Range<Int>) -> Int? {
        var index = range.lowerBound
        while index < range.upperBound {
            if units[index] == unit { return index }
            index += 1
        }
        return nil
    }

    func skipSpacesAndTabs(from index: Int, to limit: Int) -> Int {
        var cursor = index
        while cursor < limit, Self.isSpaceOrTab(units[cursor]) {
            cursor += 1
        }
        return cursor
    }

    func trimmedRange(_ range: Range<Int>) -> Range<Int> {
        var lower = range.lowerBound
        var upper = range.upperBound
        while lower < upper, Self.isSpaceOrTab(units[lower]) { lower += 1 }
        while upper > lower, Self.isSpaceOrTab(units[upper - 1]) { upper -= 1 }
        return lower..<upper
    }

    static let lineFeed: UInt16 = 10
    static let carriageReturn: UInt16 = 13
    static let space: UInt16 = 32
    static let tab: UInt16 = 9

    static func isSpaceOrTab(_ unit: UInt16) -> Bool {
        unit == space || unit == tab
    }

    static func isNewline(_ unit: UInt16) -> Bool {
        unit == lineFeed || unit == carriageReturn
    }

    static func isJavaWhitespace(_ unit: UInt16) -> Bool {
        switch unit {
        case 0x09...0x0D, 0x1C...0x1F, 0x20:
            return true
        case 0xA0, 0x2007, 0x202F:
            return false
        default:
            guard let scalar = Unicode.Scalar(unit) else { return false }
            switch scalar.properties.generalCategory {
            case .spaceSeparator, .lineSeparator, .paragraphSeparator:
                return true
            default:
                return false
            }
        }
    }

    static func isLetterOrDigit(_ unit: UInt16) -> Bool {
        guard let scalar = Unicode.Scalar(unit) else { return false }
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter, .decimalNumber:
            return true
        default:
            return false
        }
    }
}
