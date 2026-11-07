import Foundation

nonisolated struct FindModel: Equatable, Sendable {
    nonisolated enum TextAnchor: Equatable, Sendable {
        case anywhere
        case wordStart
        case wordEnd
    }

    nonisolated struct Replacement: Equatable, Sendable {
        let text: String
        let replacedCount: Int
    }

    var stringToFind = ""
    var stringToReplace = ""
    var isReplaceState = false
    var isWholeWordsOnly = false
    var isRegularExpressions = false
    var isCaseSensitive = false
    var isMultiline = false
    var isPreserveCase = false
    var isProjectScope = true
    var directoryName: String?
    var isWithSubdirectories = true
    var fileFilter: String?
    var textAnchor: TextAnchor = .anywhere

    mutating func initStringToFind(_ text: String?) {
        guard let text, !text.isEmpty else { return }
        if text.contains(where: \.isNewline) {
            isMultiline = true
        }
        stringToFind = text
    }

    func compileRegExp() -> NSRegularExpression? {
        var options: NSRegularExpression.Options = [.anchorsMatchLines]
        if !isCaseSensitive {
            options.insert(.caseInsensitive)
        }
        return try? NSRegularExpression(pattern: stringToFind, options: options)
    }

    func compileMatcher() -> NSRegularExpression? {
        guard !stringToFind.isEmpty else { return nil }
        if isRegularExpressions {
            return compileRegExp()
        }
        var pattern = NSRegularExpression.escapedPattern(for: stringToFind)
        switch textAnchor {
        case .anywhere: break
        case .wordStart: pattern = "\\b" + pattern
        case .wordEnd: pattern += "\\b"
        }
        return try? NSRegularExpression(pattern: pattern, options: isCaseSensitive ? [] : [.caseInsensitive])
    }

    func findMatches(
        in text: String,
        using regex: NSRegularExpression,
        range: NSRange? = nil
    ) -> [NSTextCheckingResult] {
        let nsText = text as NSString
        let searchRange = range ?? NSRange(location: 0, length: nsText.length)
        let options: NSRegularExpression.MatchingOptions = [.withTransparentBounds, .withoutAnchoringBounds]
        guard isWholeWordsOnly else {
            return regex.matches(in: text, options: options, range: searchRange)
        }

        var results: [NSTextCheckingResult] = []
        var offset = searchRange.location
        let end = NSMaxRange(searchRange)
        while offset <= end {
            let remaining = NSRange(location: offset, length: end - offset)
            guard let match = regex.firstMatch(in: text, options: options, range: remaining) else { break }
            if Self.isWholeWord(in: nsText, range: match.range) {
                results.append(match)
                offset = NSMaxRange(match.range) + (match.range.length == 0 ? 1 : 0)
            } else {
                offset = match.range.location + 1
            }
        }
        return results
    }

    func replacement(
        for match: NSTextCheckingResult,
        in text: NSString,
        using regex: NSRegularExpression
    ) throws -> String {
        var replacement = stringToReplace
        if isRegularExpressions {
            replacement = try RegexReplacement.createReplacement(
                template: stringToReplace,
                match: match,
                in: text,
                regex: regex
            )
        }
        if isPreserveCase {
            replacement = PreserveCase.applyCase(found: text.substring(with: match.range), replacement: replacement)
        }
        return replacement
    }

    func replaceAll(
        in text: String,
        using regex: NSRegularExpression,
        range: NSRange? = nil
    ) throws -> Replacement {
        let matches = findMatches(in: text, using: regex, range: range)
        guard !matches.isEmpty else { return Replacement(text: text, replacedCount: 0) }

        let nsText = text as NSString
        var output = ""
        var cursor = 0
        for match in matches {
            output += nsText.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            output += try replacement(for: match, in: nsText, using: regex)
            cursor = NSMaxRange(match.range)
        }
        output += nsText.substring(from: cursor)
        return Replacement(text: output, replacedCount: matches.count)
    }

    func noRestartSearchNeeded(comparedTo oldModel: FindModel) -> Bool {
        var adjusted = self
        adjusted.isPreserveCase = oldModel.isPreserveCase
        adjusted.isReplaceState = oldModel.isReplaceState
        adjusted.stringToReplace = oldModel.stringToReplace
        return adjusted == oldModel
    }

    static func isWholeWord(in text: NSString, range: NSRange) -> Bool {
        let startOffset = range.location
        let endOffset = NSMaxRange(range)
        guard startOffset >= 0, endOffset <= text.length, startOffset <= endOffset else { return false }

        let isWordStart: Bool
        if startOffset != 0, startOffset < text.length {
            let previous = text.character(at: startOffset - 1)
            let first = text.character(at: startOffset)
            let previousIsIdentifier = isIdentifierPart(previous)
                && (startOffset <= 1 || text.character(at: startOffset - 2) != backslash)
            let previousIsSameAsNext = previous == first
            isWordStart = isIdentifierPart(first) ? !previousIsIdentifier : !previousIsSameAsNext
        } else if startOffset != 0 {
            isWordStart = !isIdentifierPart(text.character(at: startOffset - 1))
        } else {
            isWordStart = true
        }

        let isWordEnd: Bool
        if endOffset != text.length {
            let next = text.character(at: endOffset)
            if endOffset > 0 {
                let last = text.character(at: endOffset - 1)
                isWordEnd = isIdentifierPart(last) ? !isIdentifierPart(next) : next != last
            } else {
                isWordEnd = true
            }
        } else {
            isWordEnd = true
        }

        return isWordStart && isWordEnd
    }

    private static let backslash = unichar(0x5C)

    private static func isIdentifierPart(_ unit: unichar) -> Bool {
        guard let scalar = Unicode.Scalar(unit) else { return false }
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .decimalNumber, .letterNumber, .currencySymbol, .connectorPunctuation,
             .nonspacingMark, .spacingMark, .format:
            return true
        default:
            return unit <= 0x08 || (0x0E...0x1B).contains(unit) || (0x7F...0x9F).contains(unit)
        }
    }
}

nonisolated struct FindScope: Sendable {
    let directoryPaths: [String]
    let includesSubdirectories: Bool

    func contains(_ fileURL: URL) -> Bool {
        if includesSubdirectories {
            let path = fileURL.path
            return directoryPaths.contains { path.hasPrefix($0 + "/") }
        }
        let parent = fileURL.deletingLastPathComponent().path
        return directoryPaths.contains(parent)
    }
}

nonisolated extension FindModel {
    func makeScope(projectRoot: URL?) -> FindScope? {
        guard !isProjectScope, let name = directoryName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else { return nil }

        let expanded = (name as NSString).expandingTildeInPath
        let directory: URL
        if expanded.hasPrefix("/") {
            directory = URL(fileURLWithPath: expanded, isDirectory: true)
        } else if let projectRoot {
            directory = projectRoot.appending(path: expanded, directoryHint: .isDirectory)
        } else {
            directory = URL(fileURLWithPath: expanded, isDirectory: true)
        }

        var paths = [directory.standardizedFileURL.path]
        let resolved = directory.resolvingSymlinksInPath().path
        if !paths.contains(resolved) {
            paths.append(resolved)
        }
        return FindScope(directoryPaths: paths, includesSubdirectories: isWithSubdirectories)
    }

    func accepts(_ fileURL: URL, scope: FindScope?, mask: FileMask) -> Bool {
        (scope?.contains(fileURL) ?? true) && mask.accepts(fileURL.lastPathComponent)
    }
}
