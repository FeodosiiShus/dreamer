import Foundation
import LanguageServerProtocol

struct LSPReferenceLocation: Hashable {
    let uri: String
    let line: Int
    let startCharacter: Int
    let endCharacter: Int
}

struct LSPUsageRow: Identifiable, Hashable {
    let uri: String
    let fileURL: URL
    let fileName: String
    let fileIconName: String
    let relativeDirectory: String
    let line: Int
    let column: Int
    let lineText: String
    let matchRange: NSRange?

    var id: String { "\(uri)#\(line)" }

    var displayLine: Int { line + 1 }
}

enum LSPUsagesMapping {
    static func locations(from response: [Location]?) -> [LSPReferenceLocation] {
        (response ?? []).map { location in
            LSPReferenceLocation(
                uri: location.uri,
                line: location.range.start.line,
                startCharacter: location.range.start.character,
                endCharacter: location.range.end.character
            )
        }
    }

    static func rows(
        from locations: [LSPReferenceLocation],
        fileTexts: [String: String],
        workspacePath: String?
    ) -> [LSPUsageRow] {
        let entries: [(url: URL, location: LSPReferenceLocation)] = locations.compactMap { location in
            guard let url = LSPDiagnosticMapping.fileURL(fromDocumentURI: location.uri) else { return nil }
            return (url, location)
        }
        let ordered = entries.sorted { lhs, rhs in
            if lhs.url.path != rhs.url.path { return lhs.url.path < rhs.url.path }
            if lhs.location.line != rhs.location.line { return lhs.location.line < rhs.location.line }
            return lhs.location.startCharacter < rhs.location.startCharacter
        }

        var lineCache: [String: [[UTF16.CodeUnit]]] = [:]
        var seen: Set<String> = []
        var rows: [LSPUsageRow] = []

        for entry in ordered {
            let key = "\(entry.url.path)#\(entry.location.line)"
            guard seen.insert(key).inserted else { continue }

            let units: [[UTF16.CodeUnit]]
            if let cached = lineCache[entry.location.uri] {
                units = cached
            } else {
                units = lineUnits(in: fileTexts[entry.location.uri] ?? "")
                lineCache[entry.location.uri] = units
            }

            let rowLine = units.indices.contains(entry.location.line) ? units[entry.location.line] : []
            let display = displayLine(
                from: rowLine,
                startCharacter: entry.location.startCharacter,
                endCharacter: entry.location.endCharacter
            )
            rows.append(LSPUsageRow(
                uri: entry.location.uri,
                fileURL: entry.url,
                fileName: entry.url.lastPathComponent,
                fileIconName: IntelliJIcon.fileIcon(for: entry.url.lastPathComponent),
                relativeDirectory: relativeDirectory(for: entry.url, workspacePath: workspacePath),
                line: entry.location.line,
                column: entry.location.startCharacter,
                lineText: display.text,
                matchRange: display.matchRange
            ))
        }
        return rows
    }

    static func lineUnits(in text: String) -> [[UTF16.CodeUnit]] {
        let units = Array(text.utf16)
        var lines: [[UTF16.CodeUnit]] = []
        var current: [UTF16.CodeUnit] = []
        for unit in units {
            if unit == 0x0A {
                if current.last == 0x0D {
                    current.removeLast()
                }
                lines.append(current)
                current = []
            } else {
                current.append(unit)
            }
        }
        if units.last == 0x0A || !current.isEmpty || lines.isEmpty {
            lines.append(current)
        }
        return lines
    }

    static func displayLine(
        from units: [UTF16.CodeUnit],
        startCharacter: Int,
        endCharacter: Int
    ) -> (text: String, matchRange: NSRange?) {
        var leading = 0
        while leading < units.count, isWhitespace(units[leading]) { leading += 1 }
        var trailing = units.count
        while trailing > leading, isWhitespace(units[trailing - 1]) { trailing -= 1 }

        let trimmed = Array(units[leading..<trailing])
        let text = String(decoding: trimmed, as: UTF16.self)
        var start = min(max(startCharacter - leading, 0), trimmed.count)
        var end = min(max(endCharacter - leading, start), trimmed.count)
        if end <= start {
            let bounds = wordBounds(in: trimmed, around: start)
            start = bounds.lowerBound
            end = bounds.upperBound
        }
        let matchRange = end > start ? NSRange(location: start, length: end - start) : nil
        return (text, matchRange)
    }

    static func symbol(inLine line: String, character: Int) -> String {
        let units = Array(line.utf16)
        let bounds = wordBounds(in: units, around: character)
        guard bounds.lowerBound < bounds.upperBound else { return "" }
        return String(decoding: units[bounds.lowerBound..<bounds.upperBound], as: UTF16.self)
    }

    static func relativeDirectory(for url: URL, workspacePath: String?) -> String {
        var directory = url.deletingLastPathComponent().path(percentEncoded: false)
        if directory.count > 1, directory.hasSuffix("/") {
            directory.removeLast()
        }
        guard let workspacePath, !workspacePath.isEmpty else {
            return (directory as NSString).abbreviatingWithTildeInPath
        }
        if directory == workspacePath { return "" }
        let prefix = workspacePath.hasSuffix("/") ? workspacePath : workspacePath + "/"
        if directory.hasPrefix(prefix) {
            return String(directory.dropFirst(prefix.count))
        }
        return (directory as NSString).abbreviatingWithTildeInPath
    }

    private static func wordBounds(in units: [UTF16.CodeUnit], around offset: Int) -> Range<Int> {
        var lower = min(max(offset, 0), units.count)
        var upper = lower
        if lower < units.count, isIdentifier(units[lower]) {
            upper = lower + 1
        } else if lower > 0, isIdentifier(units[lower - 1]) {
            lower -= 1
            upper = lower + 1
        } else {
            return lower..<lower
        }
        while lower > 0, isIdentifier(units[lower - 1]) { lower -= 1 }
        while upper < units.count, isIdentifier(units[upper]) { upper += 1 }
        return lower..<upper
    }

    private static func isWhitespace(_ character: UTF16.CodeUnit) -> Bool {
        character == 0x20 || character == 0x09 || character == 0x0B
            || character == 0x0C || character == 0xA0
    }

    private static func isIdentifier(_ character: UTF16.CodeUnit) -> Bool {
        if character == 0x5F || character == 0x24 { return true }
        if character >= 0x30, character <= 0x39 { return true }
        if character >= 0x41, character <= 0x5A { return true }
        if character >= 0x61, character <= 0x7A { return true }
        return character >= 0x80
    }
}
