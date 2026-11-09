//
//  SearchResultLineMatchModel.swift
//  DreamderModules/Search
//
//  Created by Khan Winter on 7/6/22.
//

import Foundation
import Cocoa

/// A struct for holding information about a search match.
class SearchResultMatchModel: Hashable, Identifiable {
    init(
        rangeWithinFile: Range<String.Index>,
        file: CEWorkspaceFile,
        lineContent: String,
        keywordRange: Range<String.Index>,
        usage: FindUsage? = nil
    ) {
        self.id = UUID()
        self.file = file
        self.rangeWithinFile = rangeWithinFile
        self.lineContent = lineContent
        self.keywordRange = keywordRange
        self.usage = usage
    }

    var id: UUID
    var file: CEWorkspaceFile
    var rangeWithinFile: Range<String.Index>
    var lineContent: String
    var keywordRange: Range<String.Index>
    var usage: FindUsage?
    var isSkipped = false

    static func == (lhs: SearchResultMatchModel, rhs: SearchResultMatchModel) -> Bool {
        return lhs.id == rhs.id
        && lhs.file == rhs.file
        && lhs.rangeWithinFile == rhs.rangeWithinFile
        && lhs.lineContent == rhs.lineContent
        && lhs.keywordRange == rhs.keywordRange
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(file)
        hasher.combine(rangeWithinFile)
        hasher.combine(lineContent)
        hasher.combine(keywordRange)
    }

    /// Returns a formatted `NSAttributedString` with the search result bolded.
    /// Will only return 60 characters before and after the matched result.
    /// - Returns: The formatted `NSAttributedString`
    func attributedLabel() -> NSAttributedString {
        // By default `NSTextView` will ignore any paragraph wrapping set to the label when it's
        // using an `NSAttributedString` so we need to set the wrap mode here.
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byCharWrapping

        let normalAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(
                ofSize: 13,
                weight: .regular
            ),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraphStyle
        ]
        let boldAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(
                ofSize: 13,
                weight: .bold
            ),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle
        ]

        // Set up the search result string with the matched search in bold.
        let prefix = String(lineContent[..<keywordRange.lowerBound])
        let searchMatch = String(lineContent[keywordRange])
        let postfix = String(lineContent[keywordRange.upperBound...])

        let attributedString = NSMutableAttributedString(
            string: prefix,
            attributes: normalAttributes
        )
        attributedString.append(NSAttributedString(
            string: searchMatch,
            attributes: boldAttributes
        ))
        attributedString.append(NSAttributedString(
            string: postfix,
            attributes: normalAttributes
        ))

        return attributedString
    }
}

nonisolated struct FileMatchSnapshot: Sendable {
    static let contextLength = 60
    static let maxKeywordLength = 120
    static let lineBreakGlyph: Character = "⏎"

    let rangeWithinFile: Range<String.Index>
    let lineContent: String
    let keywordRange: Range<String.Index>

    static func make(matchRange: NSRange, in content: String) -> FileMatchSnapshot? {
        let text = content as NSString
        guard matchRange.location != NSNotFound,
              NSMaxRange(matchRange) <= text.length,
              let fileRange = Range(matchRange, in: content) else { return nil }

        var contextStart = max(matchRange.location - contextLength, 0)
        if contextStart > 0 {
            contextStart = text.rangeOfComposedCharacterSequence(at: contextStart).location
        }
        var lineStart = contextStart
        if matchRange.location > contextStart {
            let newline = text.range(
                of: "\n",
                options: .backwards,
                range: NSRange(location: contextStart, length: matchRange.location - contextStart)
            )
            if newline.location != NSNotFound {
                lineStart = NSMaxRange(newline)
            }
        }
        let before = text.substring(with: NSRange(location: lineStart, length: matchRange.location - lineStart))
        let leading = String(before.drop(while: \.isWhitespace))

        let keyword = displayText(for: text.substring(with: matchRange))

        let afterStart = NSMaxRange(matchRange)
        var afterEnd = min(afterStart + contextLength, text.length)
        if afterEnd > afterStart, afterEnd < text.length {
            afterEnd = NSMaxRange(text.rangeOfComposedCharacterSequence(at: afterEnd - 1))
        }
        var after = text.substring(with: NSRange(location: afterStart, length: afterEnd - afterStart))
        if let newline = after.firstIndex(where: \.isNewline) {
            after = String(after[..<newline])
        }
        after = String(after.reversed().drop(while: \.isWhitespace).reversed())

        let lineContent = leading + keyword + after
        let units = lineContent.utf16
        let keywordLower = units.index(units.startIndex, offsetBy: leading.utf16.count)
        let keywordUpper = units.index(keywordLower, offsetBy: keyword.utf16.count)
        return FileMatchSnapshot(
            rangeWithinFile: fileRange,
            lineContent: lineContent,
            keywordRange: keywordLower..<keywordUpper
        )
    }

    static func displayText(for matched: String) -> String {
        var display = ""
        var count = 0
        for character in matched {
            if count == maxKeywordLength {
                display.append("…")
                break
            }
            display.append(character.isNewline ? lineBreakGlyph : character)
            count += 1
        }
        return display
    }
}
