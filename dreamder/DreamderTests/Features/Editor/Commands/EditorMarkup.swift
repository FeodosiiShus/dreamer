import Foundation

nonisolated struct EditorMarkup: Equatable, Sendable {
    let text: String
    let selections: [NSRange]

    init(text: String, selections: [NSRange]) {
        self.text = text
        self.selections = selections.sorted { $0.location < $1.location }
    }

    init(_ markup: String) {
        var text = ""
        var offset = 0
        var selections: [NSRange] = []
        var selectionStart: Int?
        var lastSelectionEnd: Int?
        var remaining = Substring(markup)
        while let first = remaining.first {
            if remaining.hasPrefix("<selection>") {
                selectionStart = offset
                remaining = remaining.dropFirst("<selection>".count)
            } else if remaining.hasPrefix("</selection>") {
                if let start = selectionStart {
                    selections.append(NSRange(location: start, length: offset - start))
                    lastSelectionEnd = offset
                }
                selectionStart = nil
                remaining = remaining.dropFirst("</selection>".count)
            } else if remaining.hasPrefix("<caret>") {
                if selectionStart == nil && lastSelectionEnd != offset {
                    selections.append(NSRange(location: offset, length: 0))
                }
                remaining = remaining.dropFirst("<caret>".count)
            } else {
                text.append(first)
                offset += String(first).utf16.count
                remaining = remaining.dropFirst()
            }
        }
        self.init(text: text, selections: selections)
    }

    var rendered: String {
        enum Token: Int {
            case close = 0
            case caret = 1
            case open = 2
        }
        var insertions: [(offset: Int, token: Token, text: String)] = []
        for selection in selections {
            if selection.length == 0 {
                insertions.append((selection.location, .caret, "<caret>"))
            } else {
                insertions.append((selection.location, .open, "<selection>"))
                insertions.append((selection.location + selection.length, .close, "<caret></selection>"))
            }
        }
        insertions.sort { ($0.offset, $0.token.rawValue) < ($1.offset, $1.token.rawValue) }
        let units = Array(text.utf16)
        var output: [UInt16] = []
        var cursor = 0
        for insertion in insertions {
            let clamped = min(max(insertion.offset, 0), units.count)
            output.append(contentsOf: units[cursor..<clamped])
            output.append(contentsOf: Array(insertion.text.utf16))
            cursor = clamped
        }
        output.append(contentsOf: units[cursor...])
        return String(decoding: output, as: UTF16.self)
    }

    static func normalized(_ markup: String) -> String {
        EditorMarkup(markup).rendered
    }
}
