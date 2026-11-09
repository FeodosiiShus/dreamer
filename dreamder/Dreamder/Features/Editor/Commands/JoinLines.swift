import Foundation

nonisolated enum JoinLines {
    private struct Session {
        let storage: NSMutableString
        var positions: [Int]

        var length: Int { storage.length }

        func isWhitespace(at offset: Int) -> Bool {
            let unit = storage.character(at: offset)
            return unit == 0x20 || (0x09...0x0D).contains(unit) || (0x1C...0x1F).contains(unit)
        }

        func skipWhitespaceBackward(from offset: Int) -> Int {
            var cursor = offset
            while cursor > 0, isWhitespace(at: cursor - 1) {
                cursor -= 1
            }
            return cursor
        }

        func skipWhitespaceForward(from offset: Int) -> Int {
            var cursor = offset
            while cursor < length, isWhitespace(at: cursor) {
                cursor += 1
            }
            return cursor
        }

        func hasPrefix(_ prefix: String, at offset: Int) -> Bool {
            let units = Array(prefix.utf16)
            guard offset + units.count <= length else { return false }
            return units.indices.allSatisfy { storage.character(at: offset + $0) == units[$0] }
        }

        func isClosingPunctuation(at offset: Int) -> Bool {
            let unit = storage.character(at: offset)
            return unit == 0x29 || unit == 0x5D || unit == 0x2C
        }

        mutating func replace(_ range: Range<Int>, with replacement: String, markers: inout [Int]) {
            let delta = replacement.utf16.count - range.count
            storage.replaceCharacters(in: NSRange(location: range.lowerBound, length: range.count), with: replacement)
            let remap = { (offset: Int) -> Int in
                if offset <= range.lowerBound { return offset }
                if offset >= range.upperBound { return offset + delta }
                return range.lowerBound
            }
            positions = positions.map(remap)
            markers = markers.map(remap)
        }
    }

    private struct MarkerPlan {
        let skipsCommentPrefix: Bool
        let spaces: Int
    }

    static func perform(
        in text: NSString,
        selections: [NSRange],
        lineCommentPrefix: String? = nil
    ) -> EditorCommandResult? {
        guard !selections.isEmpty else { return nil }
        var session = Session(
            storage: NSMutableString(string: text as String),
            positions: selections.flatMap { [$0.location, NSMaxRange($0)] }
        )
        for selectionIndex in selections.indices {
            join(selectionIndex, in: &session, lineCommentPrefix: lineCommentPrefix)
        }
        guard let edit = hullEdit(from: text, to: session.storage) else { return nil }
        let resulting = selections.indices.map {
            NSRange(location: session.positions[2 * $0], length: session.positions[2 * $0 + 1] - session.positions[2 * $0])
        }
        return EditorCommandResult(edits: [edit], selections: resulting)
    }

    private static func join(_ selectionIndex: Int, in session: inout Session, lineCommentPrefix: String?) {
        let start = session.positions[2 * selectionIndex]
        let end = session.positions[2 * selectionIndex + 1]
        let hasSelection = end > start
        let lines = EditorLineIndex(session.storage)
        let startLine = lines.lineIndex(containing: start)
        var endLine = startLine + 1
        if hasSelection {
            endLine = lines.lineIndex(containing: end)
            if lines.lines[endLine].start == end {
                endLine -= 1
            }
        }
        guard endLine < lines.count else { return }

        var markers: [Int] = []
        var caretRestoreOffset: Int?
        for _ in 0..<(endLine - startLine) {
            let line = EditorLineIndex(session.storage).lines[startLine]
            if session.skipWhitespaceBackward(from: line.contentEnd) == line.start {
                let firstNonSpaceInNextLine = session.skipWhitespaceForward(from: line.end)
                session.replace(line.start..<firstNonSpaceInNextLine, with: "", markers: &markers)
                caretRestoreOffset = caretRestoreOffset ?? line.start
            } else {
                session.replace(line.contentEnd..<line.end, with: "", markers: &markers)
                markers.append(line.contentEnd)
            }
        }

        let commentPrefix = lineCommentPrefix.flatMap { $0.isEmpty ? nil : $0 }
        let prefixLength = commentPrefix?.utf16.count ?? 0
        let mergedLineStart = EditorLineIndex(session.storage).lines[startLine].start
        let continuationPrefix = commentPrefix.flatMap {
            session.hasPrefix($0, at: session.skipWhitespaceForward(from: mergedLineStart)) ? $0 : nil
        }
        let plans = markers.reversed().map { marker -> MarkerPlan in
            let firstContent = session.skipWhitespaceForward(from: marker)
            let continuesComment = continuationPrefix.map { session.hasPrefix($0, at: firstContent) } ?? false
            let contentStart = continuesComment
                ? session.skipWhitespaceForward(from: firstContent + prefixLength)
                : firstContent
            let needsSpace = contentStart < session.length && !session.isClosingPunctuation(at: contentStart)
            return MarkerPlan(skipsCommentPrefix: continuesComment, spaces: needsSpace ? 1 : 0)
        }
        for (processed, markerIndex) in markers.indices.reversed().enumerated() {
            let marker = markers[markerIndex]
            let plan = plans[processed]
            let replaceStart = session.skipWhitespaceBackward(from: marker)
            var replaceEnd = session.skipWhitespaceForward(from: marker)
            if plan.skipsCommentPrefix {
                replaceEnd = session.skipWhitespaceForward(from: replaceEnd + prefixLength)
            }
            caretRestoreOffset = caretRestoreOffset ?? replaceStart
            session.replace(
                replaceStart..<replaceEnd,
                with: String(repeating: " ", count: plan.spaces),
                markers: &markers
            )
        }

        if !hasSelection, let restore = caretRestoreOffset {
            session.positions[2 * selectionIndex] = restore
            session.positions[2 * selectionIndex + 1] = restore
        }
    }

    private static func hullEdit(from original: NSString, to updated: NSString) -> EditorTextEdit? {
        let originalLength = original.length
        let updatedLength = updated.length
        let shortest = min(originalLength, updatedLength)
        var prefix = 0
        while prefix < shortest, original.character(at: prefix) == updated.character(at: prefix) {
            prefix += 1
        }
        guard prefix < originalLength || prefix < updatedLength else { return nil }
        var suffix = 0
        while suffix < shortest - prefix,
            original.character(at: originalLength - 1 - suffix) == updated.character(at: updatedLength - 1 - suffix)
        {
            suffix += 1
        }
        return EditorTextEdit(
            range: NSRange(location: prefix, length: originalLength - prefix - suffix),
            replacement: updated.substring(with: NSRange(location: prefix, length: updatedLength - prefix - suffix))
        )
    }
}
