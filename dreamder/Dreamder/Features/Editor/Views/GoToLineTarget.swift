import Foundation

nonisolated struct GoToLineTarget: Equatable, Sendable {
    let line: Int
    let column: Int?
}

nonisolated enum GoToLineInput {
    static func parse(_ text: String, lineCount: Int, currentLine: Int) -> GoToLineTarget? {
        let lastLine = max(1, lineCount)
        if let components = absoluteComponents(of: text) {
            let line = Int(components.line) ?? currentLine
            guard line > 0 else { return nil }
            let column = max(1, Int(components.column) ?? 1)
            return GoToLineTarget(line: min(line, lastLine), column: column)
        }
        guard let token = relativeToken(of: text), let relative = Int(token) else { return nil }
        let clampedRelative = max(-lastLine, min(lastLine, relative))
        let line = max(1, min(lastLine, currentLine + clampedRelative))
        return GoToLineTarget(line: line, column: 1)
    }

    private static func absoluteComponents(of text: String) -> (line: String, column: String)? {
        var rest = Substring(text)
        skipWhitespace(&rest)
        let line = takeDigits(&rest)
        skipWhitespace(&rest)
        if let first = rest.first, first == "," || first == ":" {
            rest.removeFirst()
        }
        skipWhitespace(&rest)
        let column = takeDigits(&rest)
        skipWhitespace(&rest)
        return rest.isEmpty ? (line, column) : nil
    }

    private static func relativeToken(of text: String) -> String? {
        var rest = Substring(text)
        skipWhitespace(&rest)
        guard let sign = rest.first, sign == "+" || sign == "-" else { return nil }
        rest.removeFirst()
        let digits = takeDigits(&rest)
        skipWhitespace(&rest)
        guard !digits.isEmpty, rest.isEmpty else { return nil }
        return String(sign) + digits
    }

    private static func skipWhitespace(_ text: inout Substring) {
        text = text.drop(while: \.isWhitespace)
    }

    private static func takeDigits(_ text: inout Substring) -> String {
        let digits = text.prefix(while: { ("0"..."9").contains($0) })
        text = text.dropFirst(digits.count)
        return String(digits)
    }
}
