import AppKit
import SwiftUI

enum DiffColors {
    static let inserted = Color(hex: 0x294436)
    static let deleted = Color(hex: 0x484A4A)
    static let modified = Color(hex: 0x374752)
}

enum DiffCodeStyle {
    static let tabWidth = 4

    static func display(_ line: String) -> String {
        line.contains("\t") ? line.replacingOccurrences(of: "\t", with: String(repeating: " ", count: tabWidth)) : line
    }

    static func columns(in line: String) -> Int {
        var columns = 0
        for character in line {
            columns += character == "\t" ? tabWidth : 1
            if columns > 4000 {
                return columns
            }
        }
        return columns
    }
}

struct DiffLayoutMetrics: Equatable {
    let rowHeight: CGFloat
    let leftLineNumberWidth: CGFloat
    let rightLineNumberWidth: CGFloat
    let leftCodeWidth: CGFloat
    let rightCodeWidth: CGFloat

    static let empty = DiffLayoutMetrics(
        rowHeight: 20,
        leftLineNumberWidth: 40,
        rightLineNumberWidth: 40,
        leftCodeWidth: 400,
        rightCodeWidth: 400
    )

    static func make(for diff: TextDiff) -> DiffLayoutMetrics {
        let font = Islands.codeNSFont
        let characterWidth = max(("0" as NSString).size(withAttributes: [.font: font]).width, 1)
        let rowHeight = max(18, (font.ascender - font.descender + font.leading).rounded(.up) + 4)

        return DiffLayoutMetrics(
            rowHeight: rowHeight,
            leftLineNumberWidth: lineNumberWidth(lines: diff.leftLines.count, characterWidth: characterWidth),
            rightLineNumberWidth: lineNumberWidth(lines: diff.rightLines.count, characterWidth: characterWidth),
            leftCodeWidth: codeWidth(lines: diff.leftLines, characterWidth: characterWidth),
            rightCodeWidth: codeWidth(lines: diff.rightLines, characterWidth: characterWidth)
        )
    }

    private static func lineNumberWidth(lines: Int, characterWidth: CGFloat) -> CGFloat {
        let digits = CGFloat(String(max(lines, 1)).count)
        return max(34, (digits * characterWidth).rounded(.up) + 16)
    }

    private static func codeWidth(lines: [String], characterWidth: CGFloat) -> CGFloat {
        var columns = 0
        for line in lines {
            columns = max(columns, DiffCodeStyle.columns(in: line))
        }
        let width = CGFloat(columns) * characterWidth + 20
        return min(max(width, 260), 4000)
    }
}

extension GitStatus {
    var fileStatusColor: Color {
        switch self {
        case .added:
            return Islands.fileAdded
        case .deleted:
            return Islands.fileDeleted
        case .untracked:
            return Islands.fileUnversioned
        case .unmerged:
            return Islands.fileConflict
        default:
            return Islands.fileModified
        }
    }
}

enum DiffPath {
    static func relativePath(of url: URL, from root: URL) -> String {
        var rootPath = root.absoluteURL.standardizedFileURL.path(percentEncoded: false)
        while rootPath.count > 1 && rootPath.hasSuffix("/") {
            rootPath.removeLast()
        }
        let targetPath = url.absoluteURL.standardizedFileURL.path(percentEncoded: false)
        guard targetPath.hasPrefix(rootPath) else { return "" }
        let suffix = targetPath.dropFirst(rootPath.count)
        guard suffix.isEmpty || suffix.hasPrefix("/") else { return "" }
        return suffix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
