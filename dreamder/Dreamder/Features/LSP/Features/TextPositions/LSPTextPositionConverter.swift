import CodeEditTextView
import Foundation
import LanguageServerProtocol

enum LSPTextPositionConverter {
    static func offset(of position: Position, in textView: TextView) -> Int? {
        guard let line = textView.layoutManager.textLineForIndex(Int(position.line)) else { return nil }
        let storage = textView.textStorage.mutableString
        var contentEnd = NSMaxRange(line.range)
        while contentEnd > line.range.location, isLineBreak(storage.character(at: contentEnd - 1)) {
            contentEnd -= 1
        }
        let contentLength = contentEnd - line.range.location
        return line.range.location + min(max(Int(position.character), 0), contentLength)
    }

    private static func isLineBreak(_ unit: unichar) -> Bool {
        unit == 0x0A || unit == 0x0D
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
