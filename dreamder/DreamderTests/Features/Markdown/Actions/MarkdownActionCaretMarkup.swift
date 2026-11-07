import Foundation

struct MarkdownActionCaretMarkup: Equatable {
    let text: String
    let selections: [NSRange]

    private static let caretTag = Array("<caret>".utf16)
    private static let selectionOpenTag = Array("<selection>".utf16)
    private static let selectionCloseTag = Array("</selection>".utf16)

    init(_ markup: String) {
        let source = Array(markup.utf16)
        var units: [UInt16] = []
        var selections: [NSRange] = []
        var selectionStart: Int?
        var index = 0
        while index < source.count {
            if Self.matches(Self.caretTag, in: source, at: index) {
                selections.append(NSRange(location: units.count, length: 0))
                index += Self.caretTag.count
            } else if Self.matches(Self.selectionOpenTag, in: source, at: index) {
                selectionStart = units.count
                index += Self.selectionOpenTag.count
            } else if Self.matches(Self.selectionCloseTag, in: source, at: index) {
                if let start = selectionStart {
                    selections.append(NSRange(location: start, length: units.count - start))
                    selectionStart = nil
                }
                index += Self.selectionCloseTag.count
            } else {
                units.append(source[index])
                index += 1
            }
        }
        self.text = String(decoding: units, as: UTF16.self)
        self.selections = selections
    }

    static func render(_ text: String, _ selections: [NSRange]) -> String {
        let units = Array(text.utf16)
        var insertions: [(offset: Int, order: Int, tag: [UInt16])] = []
        for selection in selections {
            if selection.length == 0 {
                insertions.append((selection.location, 1, caretTag))
            } else {
                insertions.append((selection.location, 0, selectionOpenTag))
                insertions.append((selection.location + selection.length, 2, selectionCloseTag))
            }
        }
        insertions.sort { left, right in
            left.offset != right.offset ? left.offset < right.offset : left.order < right.order
        }
        var result: [UInt16] = []
        var cursor = 0
        for insertion in insertions {
            let offset = min(max(insertion.offset, cursor), units.count)
            result.append(contentsOf: units[cursor..<offset])
            result.append(contentsOf: insertion.tag)
            cursor = offset
        }
        result.append(contentsOf: units[cursor...])
        return String(decoding: result, as: UTF16.self)
    }

    private static func matches(_ tag: [UInt16], in source: [UInt16], at index: Int) -> Bool {
        guard index + tag.count <= source.count else { return false }
        return source[index..<(index + tag.count)].elementsEqual(tag)
    }
}
