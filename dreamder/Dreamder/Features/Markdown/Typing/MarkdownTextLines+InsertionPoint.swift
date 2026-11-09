import Foundation

nonisolated extension MarkdownTextLines {
    func insertionLine(containing offset: Int) -> Int? {
        guard offset >= 0, offset <= units.count else { return nil }
        let line = lineIndex(containing: offset)
        guard offset <= lines[line].contentEnd, !Self.splitsSurrogatePair(units, at: offset) else { return nil }
        return line
    }

    static func splitsSurrogatePair(_ units: [UInt16], at offset: Int) -> Bool {
        offset > 0 && offset < units.count
            && (0xD800...0xDBFF).contains(units[offset - 1]) && (0xDC00...0xDFFF).contains(units[offset])
    }
}
