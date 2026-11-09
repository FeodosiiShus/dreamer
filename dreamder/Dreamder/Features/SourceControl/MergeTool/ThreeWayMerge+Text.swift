import Foundation

nonisolated extension ThreeWayMerge {
    var hasTrailingNewline: Bool {
        let base = LineEnding.endsWithLineBreak(baseText)
        let left = leftText.isEmpty ? base : LineEnding.endsWithLineBreak(leftText)
        let right = rightText.isEmpty ? base : LineEnding.endsWithLineBreak(rightText)
        return left == base ? right : left
    }

    var resultText: String {
        let lines = resultLines
        let text = lines.joined(separator: lineEnding.rawValue)
        guard hasTrailingNewline, !lines.isEmpty else { return text }
        return text + lineEnding.rawValue
    }
}
