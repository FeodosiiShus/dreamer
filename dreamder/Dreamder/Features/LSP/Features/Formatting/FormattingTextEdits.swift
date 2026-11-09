import Foundation
import LanguageServerProtocol

nonisolated enum FormattingTextPositions {
    private static let lineFeed: UInt16 = 0x0A
    private static let carriageReturn: UInt16 = 0x0D

    static func position(atOffset offset: Int, in units: [UInt16]) -> Position {
        let end = min(max(offset, 0), units.count)
        var line = 0
        var lineStart = 0
        var index = 0
        while index < end {
            let unit = units[index]
            if unit == carriageReturn, index + 1 < units.count, units[index + 1] == lineFeed {
                index += 1
            }
            if unit == lineFeed || unit == carriageReturn {
                line += 1
                lineStart = index + 1
            }
            index += 1
        }
        return Position(line: line, character: max(end - lineStart, 0))
    }

    static func wholeDocumentRange(of text: String) -> LSPRange {
        let units = Array(text.utf16)
        return LSPRange(
            start: Position(line: 0, character: 0),
            end: position(atOffset: units.count, in: units)
        )
    }

    static func range(of nsRange: NSRange, in units: [UInt16]) -> LSPRange {
        LSPRange(
            start: position(atOffset: nsRange.location, in: units),
            end: position(atOffset: NSMaxRange(nsRange), in: units)
        )
    }
}

nonisolated enum MinimalTextEdit {
    static func between(_ old: String, _ new: String) -> LSPResolvedTextEdit? {
        let oldUnits = Array(old.utf16)
        let newUnits = Array(new.utf16)
        guard oldUnits != newUnits else { return nil }
        let limit = min(oldUnits.count, newUnits.count)
        var prefix = 0
        while prefix < limit, oldUnits[prefix] == newUnits[prefix] {
            prefix += 1
        }
        while prefix > 0, splitsPair(oldUnits, at: prefix) || splitsPair(newUnits, at: prefix) {
            prefix -= 1
        }
        var suffix = 0
        while suffix < limit - prefix, oldUnits[oldUnits.count - 1 - suffix] == newUnits[newUnits.count - 1 - suffix] {
            suffix += 1
        }
        while suffix > 0,
              splitsPair(oldUnits, at: oldUnits.count - suffix) || splitsPair(newUnits, at: newUnits.count - suffix) {
            suffix -= 1
        }
        let oldEnd = oldUnits.count - suffix
        let replacement = String(decoding: newUnits[prefix..<(newUnits.count - suffix)], as: UTF16.self)
        let edit = TextEdit(
            range: LSPRange(
                start: FormattingTextPositions.position(atOffset: prefix, in: oldUnits),
                end: FormattingTextPositions.position(atOffset: oldEnd, in: oldUnits)
            ),
            newText: replacement
        )
        return LSPResolvedTextEdit(edit: edit, range: NSRange(location: prefix, length: oldEnd - prefix))
    }

    private static func splitsPair(_ units: [UInt16], at index: Int) -> Bool {
        guard index > 0, index < units.count else { return false }
        let before = units[index - 1]
        let after = units[index]
        let isSurrogatePair = (0xD800...0xDBFF).contains(before) && (0xDC00...0xDFFF).contains(after)
        let isCarriageReturnLineFeed = before == 0x0D && after == 0x0A
        return isSurrogatePair || isCarriageReturnLineFeed
    }
}
