import Foundation

nonisolated enum MarkdownTokenKind: Hashable, Sendable {
    case headerMarker
    case headerContent(level: Int)
    case blockQuote
    case blockQuoteMarker
    case listMarker
    case checkbox
    case horizontalRule
    case codeFenceMarker
    case codeFenceLanguage
    case codeFenceContent(hasLanguage: Bool)
    case codeBlock
    case tableSeparator
    case frontMatterDelimiter
    case frontMatterContent
    case htmlComment
    case htmlTag
    case htmlTagName
    case htmlAttributeName
    case htmlAttributeValue
    case htmlCode
    case inlineHtml
    case codeSpan
    case codeSpanMarker
    case italic
    case italicMarker
    case bold
    case boldMarker
    case strikethrough
    case highlight
    case inlineLink
    case image
    case linkText
    case linkLabel
    case linkDestination
    case linkTitle
    case autolink
    case escape
    case hardBreak

    var isComposite: Bool {
        switch self {
        case .headerContent, .blockQuote, .italic, .bold, .strikethrough, .highlight, .codeSpan,
             .inlineLink, .image, .inlineHtml, .linkText:
            true
        default:
            false
        }
    }
}

nonisolated struct MarkdownToken: Hashable, Sendable {
    let kind: MarkdownTokenKind
    let range: NSRange

    init(_ kind: MarkdownTokenKind, _ range: NSRange) {
        self.kind = kind
        self.range = range
    }

    init(_ kind: MarkdownTokenKind, from start: Int, to end: Int) {
        self.kind = kind
        self.range = NSRange(location: start, length: end - start)
    }
}

nonisolated struct MarkdownHeaderBlock: Hashable, Sendable {
    let level: Int
    let isSetext: Bool
    let contentRange: NSRange
    let range: NSRange
    let containerPath: [Int]
}

nonisolated struct MarkdownDocumentScan: Sendable {
    let tokens: [MarkdownToken]
    let headers: [MarkdownHeaderBlock]
}

extension Array where Element == MarkdownToken {
    nonisolated func sortedOuterFirst() -> [MarkdownToken] {
        enumerated()
            .sorted { lhs, rhs in
                let left = lhs.element
                let right = rhs.element
                if left.range.location != right.range.location {
                    return left.range.location < right.range.location
                }
                if left.range.length != right.range.length {
                    return left.range.length > right.range.length
                }
                if left.kind.isComposite != right.kind.isComposite {
                    return left.kind.isComposite
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}

nonisolated enum MarkdownChar {
    static let tab = UInt16(9)
    static let newline = UInt16(10)
    static let carriageReturn = UInt16(13)
    static let space = UInt16(32)
    static let exclamation = UInt16(33)
    static let doubleQuote = UInt16(34)
    static let hash = UInt16(35)
    static let ampersand = UInt16(38)
    static let singleQuote = UInt16(39)
    static let openParen = UInt16(40)
    static let closeParen = UInt16(41)
    static let star = UInt16(42)
    static let plus = UInt16(43)
    static let dash = UInt16(45)
    static let dot = UInt16(46)
    static let slash = UInt16(47)
    static let colon = UInt16(58)
    static let less = UInt16(60)
    static let equals = UInt16(61)
    static let greater = UInt16(62)
    static let question = UInt16(63)
    static let at = UInt16(64)
    static let openBracket = UInt16(91)
    static let backslash = UInt16(92)
    static let closeBracket = UInt16(93)
    static let caret = UInt16(94)
    static let underscore = UInt16(95)
    static let backtick = UInt16(96)
    static let pipe = UInt16(124)
    static let tilde = UInt16(126)
    static let nonBreakingSpace = UInt16(0xA0)
    static let comma = UInt16(44)
    static let semicolon = UInt16(59)
    static let upperF = UInt16(70)
    static let upperH = UInt16(72)
    static let upperW = UInt16(87)
    static let lowerF = UInt16(102)
    static let lowerH = UInt16(104)
    static let lowerW = UInt16(119)

    static func isSpaceOrTab(_ unit: UInt16) -> Bool {
        unit == space || unit == tab
    }

    static func isLineBreak(_ unit: UInt16) -> Bool {
        unit == newline || unit == carriageReturn
    }

    static func isASCIILetter(_ unit: UInt16) -> Bool {
        (unit >= 65 && unit <= 90) || (unit >= 97 && unit <= 122)
    }

    static func isASCIIDigit(_ unit: UInt16) -> Bool {
        unit >= 48 && unit <= 57
    }

    static func isASCIIAlphanumeric(_ unit: UInt16) -> Bool {
        isASCIILetter(unit) || isASCIIDigit(unit)
    }

    static func isASCIIPunctuation(_ unit: UInt16) -> Bool {
        (unit >= 33 && unit <= 47) || (unit >= 58 && unit <= 64) || (unit >= 91 && unit <= 96)
            || (unit >= 123 && unit <= 126)
    }

    static func isWhitespace(_ unit: UInt16) -> Bool {
        switch unit {
        case space, tab, newline, carriageReturn, 11, 12, nonBreakingSpace:
            return true
        default:
            guard unit > 127, let scalar = Unicode.Scalar(unit) else { return false }
            return scalar.properties.generalCategory == .spaceSeparator
        }
    }

    static func isPunctuation(_ unit: UInt16) -> Bool {
        if unit < 128 { return isASCIIPunctuation(unit) }
        guard let scalar = Unicode.Scalar(unit) else { return false }
        switch scalar.properties.generalCategory {
        case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
             .initialPunctuation, .finalPunctuation, .otherPunctuation,
             .mathSymbol, .currencySymbol, .modifierSymbol, .otherSymbol:
            return true
        default:
            return false
        }
    }
}
