import Foundation

nonisolated struct PartialCommitHunk: Identifiable, Hashable, Sendable {
    let oldStart: Int
    let oldCount: Int
    let newStart: Int
    let newCount: Int
    let contentHash: UInt64
    let preview: String

    var id: String {
        "\(oldStart),\(oldCount),\(newCount)#\(String(contentHash, radix: 16))"
    }

    var oldAnchor: Int {
        oldCount == 0 ? oldStart : oldStart - 1
    }

    var newAnchor: Int {
        newCount == 0 ? newStart : newStart - 1
    }

    var rangeTitle: String {
        "-\(PartialCommitPatchBuilder.rangeText(start: oldStart, count: oldCount)) "
            + "+\(PartialCommitPatchBuilder.rangeText(start: newStart, count: newCount))"
    }
}

nonisolated struct PartialCommitLines: Sendable {
    let lines: [ArraySlice<UInt8>]
    let endsWithNewline: Bool

    init(_ data: Data) {
        let bytes = [UInt8](data)
        var result: [ArraySlice<UInt8>] = []
        var start = 0
        for index in bytes.indices where bytes[index] == PartialCommitPatchBuilder.newline {
            result.append(bytes[start..<index])
            start = index + 1
        }
        let hasUnterminatedLine = start < bytes.count
        if hasUnterminatedLine {
            result.append(bytes[start..<bytes.count])
        }
        lines = result
        endsWithNewline = !hasUnterminatedLine
    }

    func isUnterminated(_ index: Int) -> Bool {
        !endsWithNewline && index == lines.count - 1
    }
}

nonisolated enum PartialCommitPatchBuilder {
    nonisolated enum Kind: Sendable {
        case modified
        case added
        case deleted
    }

    static let contextLines = 3
    static let newline: UInt8 = 10

    private static let previewLimit = 80
    private static let fnvOffset: UInt64 = 0xcbf2_9ce4_8422_2325
    private static let fnvPrime: UInt64 = 0x0000_0100_0000_01b3

    static func rangeText(start: Int, count: Int) -> String {
        count == 1 ? "\(start)" : "\(start),\(count)"
    }

    static func hunks(from headers: [GitDiffParser.Hunk], head: Data, worktree: Data) -> [PartialCommitHunk] {
        let old = PartialCommitLines(head)
        let new = PartialCommitLines(worktree)
        return headers.compactMap { header in
            let oldAnchor = header.oldCount == 0 ? header.oldStart : header.oldStart - 1
            let newAnchor = header.newCount == 0 ? header.newStart : header.newStart - 1
            guard header.oldCount + header.newCount > 0,
                  oldAnchor >= 0,
                  newAnchor >= 0,
                  oldAnchor + header.oldCount <= old.lines.count,
                  newAnchor + header.newCount <= new.lines.count else {
                return nil
            }
            let removed = old.lines[oldAnchor..<(oldAnchor + header.oldCount)]
            let added = new.lines[newAnchor..<(newAnchor + header.newCount)]
            return PartialCommitHunk(
                oldStart: header.oldStart,
                oldCount: header.oldCount,
                newStart: header.newStart,
                newCount: header.newCount,
                contentHash: contentHash(removed: removed, added: added),
                preview: preview(removed: removed, added: added)
            )
        }
    }

    static func patch(
        path: String,
        kind: Kind = .modified,
        mode: String = "100644",
        head: Data,
        worktree: Data,
        hunks: [PartialCommitHunk],
        selected: Set<String>
    ) -> Data? {
        let chosen = hunks
            .filter { selected.contains($0.id) }
            .sorted { ($0.oldAnchor, $0.newAnchor) < ($1.oldAnchor, $1.newAnchor) }
        guard !chosen.isEmpty else { return nil }

        let old = PartialCommitLines(head)
        let new = PartialCommitLines(worktree)
        var output = Data(fileHeader(path: path, kind: kind, mode: mode).utf8)
        var offset = 0
        var index = 0
        while index < chosen.count {
            let first = chosen[index]
            var group = [first]
            var groupEnd = first.oldAnchor + first.oldCount
            index += 1
            while index < chosen.count, chosen[index].oldAnchor - groupEnd <= 2 * contextLines {
                group.append(chosen[index])
                groupEnd = max(groupEnd, chosen[index].oldAnchor + chosen[index].oldCount)
                index += 1
            }
            let start = max(0, first.oldAnchor - contextLines)
            let end = min(old.lines.count, groupEnd + contextLines)
            var body = Data()
            var cursor = start
            var removedTotal = 0
            var addedTotal = 0
            for hunk in group {
                append(old, from: cursor, to: hunk.oldAnchor, prefix: " ", into: &body)
                append(old, from: hunk.oldAnchor, to: hunk.oldAnchor + hunk.oldCount, prefix: "-", into: &body)
                append(new, from: hunk.newAnchor, to: hunk.newAnchor + hunk.newCount, prefix: "+", into: &body)
                cursor = max(cursor, hunk.oldAnchor + hunk.oldCount)
                removedTotal += hunk.oldCount
                addedTotal += hunk.newCount
            }
            append(old, from: cursor, to: end, prefix: " ", into: &body)

            let oldCount = max(0, end - start)
            let newCount = max(0, oldCount - removedTotal + addedTotal)
            let oldStart = oldCount == 0 ? start : start + 1
            let newStart = newCount == 0 ? start + offset : start + offset + 1
            let header = "@@ -\(rangeText(start: oldStart, count: oldCount)) "
                + "+\(rangeText(start: newStart, count: newCount)) @@\n"
            output.append(Data(header.utf8))
            output.append(body)
            offset += addedTotal - removedTotal
        }
        return output
    }

    static func fileHeader(path: String, kind: Kind, mode: String) -> String {
        let oldName = quoted("a/" + path)
        let newName = quoted("b/" + path)
        var header = "diff --git \(oldName) \(newName)\n"
        switch kind {
        case .modified:
            header += "--- \(oldName)\n+++ \(newName)\n"
        case .added:
            header += "new file mode \(mode)\n--- /dev/null\n+++ \(newName)\n"
        case .deleted:
            header += "deleted file mode \(mode)\n--- \(oldName)\n+++ /dev/null\n"
        }
        return header
    }

    static func quoted(_ name: String) -> String {
        let needsQuoting = name.unicodeScalars.contains {
            $0 == "\"" || $0 == "\\" || $0.value < 0x20 || $0.value == 0x7F
        }
        guard needsQuoting else { return name }
        var escaped = "\""
        for scalar in name.unicodeScalars {
            switch scalar {
            case "\"": escaped += "\\\""
            case "\\": escaped += "\\\\"
            case "\t": escaped += "\\t"
            case "\n": escaped += "\\n"
            default:
                if scalar.value < 0x20 || scalar.value == 0x7F {
                    let octal = String(scalar.value, radix: 8)
                    escaped += "\\" + String(repeating: "0", count: 3 - octal.count) + octal
                } else {
                    escaped.unicodeScalars.append(scalar)
                }
            }
        }
        return escaped + "\""
    }

    private static func append(
        _ text: PartialCommitLines,
        from: Int,
        to: Int,
        prefix: String,
        into output: inout Data
    ) {
        let limit = min(to, text.lines.count)
        var index = max(from, 0)
        while index < limit {
            output.append(contentsOf: prefix.utf8)
            output.append(contentsOf: text.lines[index])
            output.append(newline)
            if text.isUnterminated(index) {
                output.append(contentsOf: "\\ No newline at end of file\n".utf8)
            }
            index += 1
        }
    }

    private static func contentHash(removed: ArraySlice<ArraySlice<UInt8>>, added: ArraySlice<ArraySlice<UInt8>>) -> UInt64 {
        var hash = fnvOffset
        for (marker, lines) in [(UInt8(ascii: "-"), removed), (UInt8(ascii: "+"), added)] {
            for line in lines {
                for byte in [marker] + line + [newline] {
                    hash = (hash ^ UInt64(byte)) &* fnvPrime
                }
            }
        }
        return hash
    }

    private static func preview(removed: ArraySlice<ArraySlice<UInt8>>, added: ArraySlice<ArraySlice<UInt8>>) -> String {
        let firstLine = (added.prefix(1) + removed.prefix(1)).prefix(1).flatMap { $0 }
        let text = String(decoding: firstLine, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return String(text.prefix(previewLimit))
    }
}

nonisolated enum PartialCommitDiffParser {
    private static let wholeFileMarkers = [
        "old mode", "new mode", "new file mode", "deleted file mode", "rename ", "copy ",
        "similarity index", "dissimilarity index", "Binary files", "GIT binary patch"
    ]

    static func hunks(inDiff output: String) -> [GitDiffParser.Hunk] {
        var result: [GitDiffParser.Hunk] = []
        for slice in output.utf8.split(separator: PartialCommitPatchBuilder.newline, omittingEmptySubsequences: false) {
            let line = String(decoding: slice, as: UTF8.self)
            if let hunk = GitDiffParser.hunk(fromHeader: Substring(line)) {
                result.append(hunk)
            } else if result.isEmpty, wholeFileMarkers.contains(where: { line.hasPrefix($0) }) {
                return []
            }
        }
        return result
    }
}
