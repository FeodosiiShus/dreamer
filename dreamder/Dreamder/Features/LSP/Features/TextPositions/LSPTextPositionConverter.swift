import CodeEditTextView
import Foundation
import LanguageServerProtocol

enum LSPTextPositionConverter {
    static func offset(of position: Position, in textView: TextView) -> Int? {
        guard let line = textView.layoutManager.textLineForIndex(Int(position.line)) else { return nil }
        let offset = line.range.location + Int(position.character)
        guard offset >= line.range.location, offset <= textView.textStorage.length else { return nil }
        return offset
    }

    static func nsRange(from range: LSPRange, in textView: TextView) -> NSRange? {
        guard let start = offset(of: range.start, in: textView),
              let end = offset(of: range.end, in: textView),
              end >= start else {
            return nil
        }
        return NSRange(location: start, length: end - start)
    }
}
