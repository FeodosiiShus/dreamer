import Foundation

nonisolated struct RecentLocationsPreviewLine: Hashable, Sendable {
    let number: Int
    let text: String
    let isCaretLine: Bool
}

nonisolated enum RecentLocationsPreview: Hashable, Sendable {
    case pending
    case emptyFile
    case lines([RecentLocationsPreviewLine])
}

nonisolated struct RecentLocationsRow: Identifiable, Hashable, Sendable {
    let place: EditorPlace
    let fileName: String
    let fileIconName: String
    let relativeDirectory: String
    let preview: RecentLocationsPreview

    var id: String {
        let carets = place.carets.map { "\($0.line):\($0.column)" }.joined(separator: ",")
        return "\(place.fileURL.path(percentEncoded: false))#\(carets)"
    }

    var title: String { "\(fileName):\(place.line)" }
}

nonisolated enum RecentLocationsMapping {
    static let linesBeforeAndAfter = 2
    static let maxLineLength = 1000

    static func rows(places: [EditorPlace], texts: [URL: String], workspacePath: String?) -> [RecentLocationsRow] {
        var lineCache: [URL: [[UTF16.CodeUnit]]] = [:]
        return places.map { place in
            let preview: RecentLocationsPreview
            if let text = texts[place.fileURL] {
                let lines: [[UTF16.CodeUnit]]
                if let cached = lineCache[place.fileURL] {
                    lines = cached
                } else {
                    lines = LSPUsagesMapping.lineUnits(in: text)
                    lineCache[place.fileURL] = lines
                }
                preview = Self.preview(lines: lines, caretLine: place.line)
            } else {
                preview = .pending
            }
            let fileName = place.fileURL.lastPathComponent
            return RecentLocationsRow(
                place: place,
                fileName: fileName,
                fileIconName: IntelliJIcon.fileIcon(for: fileName),
                relativeDirectory: LSPUsagesMapping.relativeDirectory(for: place.fileURL, workspacePath: workspacePath),
                preview: preview
            )
        }
    }

    static func preview(lines: [[UTF16.CodeUnit]], caretLine: Int) -> RecentLocationsPreview {
        guard !lines.isEmpty else { return .emptyFile }
        let lineCount = lines.count
        let line = min(max(caretLine - 1, 0), lineCount - 1)
        let context = linesBeforeAndAfter
        let before = min(context, line)
        let after = min(context, lineCount - line)
        let linesBefore = before + context - after
        let linesAfter = after + context - before
        let startLine = max(line - linesBefore, 0)
        let endLine = min(line + linesAfter, lineCount - 1)

        let blank = (startLine...endLine).map { isBlank(lines[$0]) }
        var first = startLine
        var last = endLine
        if blank.allSatisfy({ $0 }) {
            last = startLine
        } else {
            first += blank.prefix { $0 }.count
            last -= blank.reversed().prefix { $0 }.count
        }

        let kept = (first...last).map { index in
            RecentLocationsPreviewLine(
                number: index + 1,
                text: String(decoding: lines[index].prefix(maxLineLength), as: UTF16.self),
                isCaretLine: index == line
            )
        }
        if kept.map(\.text).joined(separator: "\n").isEmpty {
            return .emptyFile
        }
        return .lines(kept)
    }

    private static func isBlank(_ units: [UTF16.CodeUnit]) -> Bool {
        String(decoding: units, as: UTF16.self).allSatisfy(\.isWhitespace)
    }
}
