import Foundation

nonisolated struct EditorConfigProperties: Equatable, Sendable {
    nonisolated enum IndentStyle: String, Sendable { case tab, space }
    nonisolated enum EndOfLine: String, Sendable { case lf, cr, crlf }

    var indentStyle: IndentStyle?
    var indentSize: Int?
    var tabWidth: Int?
    var endOfLine: EndOfLine?
    var insertFinalNewline: Bool?
    var trimTrailingWhitespace: Bool?
    var charset: String?
    var maxLineLength: Int?

    static let empty = EditorConfigProperties()
}

nonisolated extension EditorConfigProperties {
    init(resolving values: [String: String]) {
        let style = values["indent_style"].flatMap(IndentStyle.init(rawValue:))
        let sizeValue = values["indent_size"]
        var size = sizeValue.flatMap(Self.positiveInt)
        var width = values["tab_width"].flatMap(Self.positiveInt)
        let sizeFollowsTabWidth = sizeValue == "tab" || (style == .tab && size == nil)
        if let size, width == nil {
            width = size
        }
        if sizeFollowsTabWidth, let width {
            size = width
        }
        let maxLength = values["max_line_length"]
        self.init(
            indentStyle: style,
            indentSize: size,
            tabWidth: width,
            endOfLine: values["end_of_line"].flatMap(EndOfLine.init(rawValue:)),
            insertFinalNewline: values["insert_final_newline"].flatMap(Self.boolean),
            trimTrailingWhitespace: values["trim_trailing_whitespace"].flatMap(Self.boolean),
            charset: values["charset"].flatMap { $0.isEmpty ? nil : $0 },
            maxLineLength: maxLength == "off" ? nil : maxLength.flatMap(Self.positiveInt)
        )
    }

    private static func positiveInt(_ text: String) -> Int? {
        guard text.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }), let number = Int(text), number > 0 else {
            return nil
        }
        return number
    }

    private static func boolean(_ text: String) -> Bool? {
        switch text {
        case "true": true
        case "false": false
        default: nil
        }
    }
}
