import Foundation

nonisolated struct MarkdownListItemPrefix: Equatable, Sendable {
    nonisolated enum Marker: Equatable, Sendable {
        case bullet(Character)
        case ordered(number: Int, delimiter: Character)
    }

    static let bulletCharacters: Set<Character> = ["-", "*", "+"]
    static let orderedDelimiters: Set<Character> = [".", ")"]

    let indent: String
    let marker: Marker
    let markerText: String
    let checkbox: Bool?
    let contentStart: Int
    let lineLength: Int
    let markerWidth: Int
    let hasContent: Bool

    var normalizedMarkerText: String {
        markerText + " "
    }

    var contentColumn: Int {
        contentStart
    }

    var checkboxText: String? {
        checkbox.map { $0 ? "[x] " : "[ ] " }
    }

    var indentLength: Int {
        indent.utf16.count
    }

    var markerTokenEnd: Int {
        indentLength + markerText.utf16.count + (contentStart > indentLength + markerText.utf16.count ? 1 : 0)
    }

    var prefixEnd: Int {
        checkbox == nil ? markerTokenEnd : contentStart
    }

    var delimiter: Character {
        switch marker {
        case .bullet(let character): character
        case .ordered(_, let delimiter): delimiter
        }
    }

    var number: Int? {
        if case .ordered(let number, _) = marker { number } else { nil }
    }

    func isSameListKind(as other: MarkdownListItemPrefix) -> Bool {
        switch (marker, other.marker) {
        case (.bullet(let lhs), .bullet(let rhs)): lhs == rhs
        case (.ordered(_, let lhs), .ordered(_, let rhs)): lhs == rhs
        default: false
        }
    }

    static func parse(line: Substring) -> MarkdownListItemPrefix? {
        parse(units: Array(line.utf16)[...])
    }

    static func parse(units: ArraySlice<UInt16>) -> MarkdownListItemPrefix? {
        let base = units.startIndex
        let end = units.endIndex
        var index = base
        while index < end, isIndentUnit(units[index]) {
            index += 1
        }
        guard index < end else { return nil }

        let indentLength = index - base
        let markerStart = index
        let marker: Marker
        let first = units[index]
        if first < 128, bulletCharacters.contains(Character(Unicode.Scalar(UInt8(first)))) {
            marker = .bullet(Character(Unicode.Scalar(UInt8(first))))
            index += 1
        } else {
            var number = 0
            var digitCount = 0
            while index < end, units[index] >= 48, units[index] <= 57, digitCount < 9 {
                number = number * 10 + Int(units[index] - 48)
                digitCount += 1
                index += 1
            }
            guard digitCount > 0, index < end, units[index] == 46 || units[index] == 41 else { return nil }
            marker = .ordered(number: number, delimiter: units[index] == 46 ? "." : ")")
            index += 1
        }
        let markerText = String(decoding: units[markerStart..<index], as: UTF16.self)

        guard index == end || isSpaceOrTab(units[index]) else { return nil }
        var run = 0
        while index + run < end, isSpaceOrTab(units[index + run]) {
            run += 1
        }
        let consumed = min(run, 4)
        index += consumed
        let markerLength = index - markerStart - consumed
        let markerWidth = markerLength + (run == 0 || run > 4 ? 1 : run)

        var checkbox: Bool?
        if end - index >= 3, units[index] == 91, units[index + 2] == 93,
           units[index + 1] == 32 || units[index + 1] == 120 || units[index + 1] == 88 {
            let afterBox = index + 3
            if afterBox == end || units[afterBox] == 32 {
                checkbox = units[index + 1] != 32
                index = afterBox < end ? afterBox + 1 : afterBox
            }
        }

        var hasContent = false
        var probe = index
        while probe < end {
            if !isSpaceOrTab(units[probe]) {
                hasContent = true
                break
            }
            probe += 1
        }

        return MarkdownListItemPrefix(
            indent: String(decoding: units[base..<(base + indentLength)], as: UTF16.self),
            marker: marker,
            markerText: markerText,
            checkbox: checkbox,
            contentStart: index - base,
            lineLength: end - base,
            markerWidth: markerWidth,
            hasContent: hasContent
        )
    }

    func nextMarkerText(sequential: Bool = true) -> String {
        switch marker {
        case .bullet:
            return markerText
        case .ordered(let number, let delimiter):
            return "\(sequential ? number + 1 : number)\(delimiter)"
        }
    }

    private static func isIndentUnit(_ unit: UInt16) -> Bool {
        unit == 32 || unit == 9 || unit == 62
    }

    private static func isSpaceOrTab(_ unit: UInt16) -> Bool {
        unit == 32 || unit == 9
    }
}
