import Foundation
@testable import Dreamder

nonisolated struct MarkdownCaretMarkup: Equatable, Sendable {
    let text: String
    let caret: Int
    let selection: NSRange?

    init(_ marked: String) {
        var output = ""
        var length = 0
        var caret: Int?
        var selectionStart: Int?
        var selectionEnd: Int?
        var rest = Substring(marked)
        let tokens = ["<caret>", "<selection>", "</selection>"]
        while !rest.isEmpty {
            let next = tokens
                .compactMap { token in rest.range(of: token).map { (token: token, range: $0) } }
                .min { $0.range.lowerBound < $1.range.lowerBound }
            guard let next else {
                output.append(contentsOf: rest)
                length += rest.utf16.count
                break
            }
            let before = rest[rest.startIndex..<next.range.lowerBound]
            output.append(contentsOf: before)
            length += before.utf16.count
            switch next.token {
            case "<caret>": caret = length
            case "<selection>": selectionStart = length
            default: selectionEnd = length
            }
            rest = rest[next.range.upperBound...]
        }
        text = output
        if let selectionStart, let selectionEnd {
            selection = NSRange(location: selectionStart, length: selectionEnd - selectionStart)
            self.caret = caret ?? selectionEnd
        } else {
            selection = nil
            self.caret = caret ?? 0
        }
    }

    static func render(_ text: String, caret: Int) -> String {
        let string = text as NSString
        return string.substring(to: caret) + "<caret>" + string.substring(from: caret)
    }
}

nonisolated enum MarkdownTypingHarness {
    static func enter(
        _ marked: String,
        shift: Bool = false,
        times: Int = 1,
        settings: MarkdownTypingSettings = MarkdownTypingSettings()
    ) -> String {
        var current = marked
        for _ in 0..<times {
            let markup = MarkdownCaretMarkup(current)
            if let edit = MarkdownListEnter.edit(forEnterIn: markup.text, caret: markup.caret, shift: shift, settings: settings) {
                let result = edit.applied(to: markup.text)
                current = MarkdownCaretMarkup.render(result.text, caret: result.caret)
            } else {
                let string = markup.text as NSString
                let inserted = string.replacingCharacters(in: NSRange(location: markup.caret, length: 0), with: "\n")
                current = MarkdownCaretMarkup.render(inserted, caret: markup.caret + 1)
            }
        }
        return current
    }

    static func backspace(
        _ marked: String,
        times: Int = 1,
        settings: MarkdownTypingSettings = MarkdownTypingSettings()
    ) -> String {
        var current = marked
        for _ in 0..<times {
            let markup = MarkdownCaretMarkup(current)
            if let edit = MarkdownListEnter.edit(forBackspaceIn: markup.text, caret: markup.caret, settings: settings) {
                let result = edit.applied(to: markup.text)
                current = MarkdownCaretMarkup.render(result.text, caret: result.caret)
            } else if markup.caret > 0 {
                let string = markup.text as NSString
                let deleted = string.replacingCharacters(in: NSRange(location: markup.caret - 1, length: 1), with: "")
                current = MarkdownCaretMarkup.render(deleted, caret: markup.caret - 1)
            }
        }
        return current
    }

    static func renumber(
        _ marked: String,
        recursive: Bool,
        restart: Bool,
        sequentially: Bool = true
    ) -> String {
        let markup = MarkdownCaretMarkup(marked)
        let state = MarkdownTextState(text: markup.text, caret: markup.caret)
        let lines = MarkdownTextLines(markup.text)
        let result = MarkdownListRenumber.renumberInBulk(
            state,
            listAtLine: lines.lineIndex(containing: markup.caret),
            recursive: recursive,
            restart: restart,
            sequentially: sequentially
        )
        return MarkdownCaretMarkup.render(result.text, caret: result.caret)
    }

    static func rawEnterEdit(
        _ marked: String,
        shift: Bool = false,
        settings: MarkdownTypingSettings = MarkdownTypingSettings()
    ) -> MarkdownTypingEdit? {
        let markup = MarkdownCaretMarkup(marked)
        return MarkdownListEnter.edit(forEnterIn: markup.text, caret: markup.caret, shift: shift, settings: settings)
    }

    static func rawBackspaceEdit(
        _ marked: String,
        settings: MarkdownTypingSettings = MarkdownTypingSettings()
    ) -> MarkdownTypingEdit? {
        let markup = MarkdownCaretMarkup(marked)
        return MarkdownListEnter.edit(forBackspaceIn: markup.text, caret: markup.caret, settings: settings)
    }
}
