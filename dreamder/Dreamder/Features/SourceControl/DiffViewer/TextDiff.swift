import Foundation

enum DiffRowKind: Equatable {
    case context
    case inserted
    case deleted
    case modified
}

struct DiffRow: Equatable {
    let leftLine: Int?
    let rightLine: Int?
    let kind: DiffRowKind
}

enum DiffHunkKind: Equatable {
    case inserted
    case deleted
    case modified
}

struct DiffHunk: Equatable, Identifiable {
    let id: Int
    let kind: DiffHunkKind
    let leftLines: Range<Int>
    let rightLines: Range<Int>
    let rows: Range<Int>
}

struct DiffOptions: Equatable {
    var ignoresWhitespace = false

    static let `default` = DiffOptions()
}

struct TextDiff: Equatable {
    let leftLines: [String]
    let rightLines: [String]
    let hunks: [DiffHunk]
    let rows: [DiffRow]

    init(left: String, right: String, options: DiffOptions = .default) {
        self.init(leftLines: Self.lines(in: left), rightLines: Self.lines(in: right), options: options)
    }

    init(leftLines: [String], rightLines: [String], options: DiffOptions = .default) {
        var hunks: [DiffHunk] = []
        var rows: [DiffRow] = []

        let leftKeys = options.ignoresWhitespace ? leftLines.map(Self.normalized) : leftLines
        let rightKeys = options.ignoresWhitespace ? rightLines.map(Self.normalized) : rightLines
        let difference: CollectionDifference<String> = rightKeys.difference(from: leftKeys)
        var removals = Set<Int>()
        var insertions = Set<Int>()
        for change in difference.removals {
            if case let .remove(offset, _, _) = change {
                removals.insert(offset)
            }
        }
        for change in difference.insertions {
            if case let .insert(offset, _, _) = change {
                insertions.insert(offset)
            }
        }

        func appendHunk(leftRange: Range<Int>, rightRange: Range<Int>) {
            let startRow = rows.count
            let kind: DiffHunkKind
            if !leftRange.isEmpty && !rightRange.isEmpty {
                kind = .modified
            } else if !leftRange.isEmpty {
                kind = .deleted
            } else {
                kind = .inserted
            }

            let paired = min(leftRange.count, rightRange.count)
            for offset in 0..<paired {
                rows.append(DiffRow(
                    leftLine: leftRange.lowerBound + offset,
                    rightLine: rightRange.lowerBound + offset,
                    kind: .modified
                ))
            }
            for offset in paired..<leftRange.count {
                rows.append(DiffRow(
                    leftLine: leftRange.lowerBound + offset,
                    rightLine: nil,
                    kind: .deleted
                ))
            }
            for offset in paired..<rightRange.count {
                rows.append(DiffRow(
                    leftLine: nil,
                    rightLine: rightRange.lowerBound + offset,
                    kind: .inserted
                ))
            }

            hunks.append(DiffHunk(
                id: hunks.count,
                kind: kind,
                leftLines: leftRange,
                rightLines: rightRange,
                rows: startRow..<rows.count
            ))
        }

        var leftIndex = 0
        var rightIndex = 0
        while leftIndex < leftLines.count || rightIndex < rightLines.count {
            if leftIndex < leftLines.count, removals.contains(leftIndex) {
                let leftStart = leftIndex
                while leftIndex < leftLines.count, removals.contains(leftIndex) {
                    leftIndex += 1
                }
                let rightStart = rightIndex
                while rightIndex < rightLines.count, insertions.contains(rightIndex) {
                    rightIndex += 1
                }
                appendHunk(leftRange: leftStart..<leftIndex, rightRange: rightStart..<rightIndex)
            } else if rightIndex < rightLines.count, insertions.contains(rightIndex) {
                let rightStart = rightIndex
                while rightIndex < rightLines.count, insertions.contains(rightIndex) {
                    rightIndex += 1
                }
                appendHunk(leftRange: leftIndex..<leftIndex, rightRange: rightStart..<rightIndex)
            } else {
                rows.append(DiffRow(leftLine: leftIndex, rightLine: rightIndex, kind: .context))
                leftIndex += 1
                rightIndex += 1
            }
        }

        self.leftLines = leftLines
        self.rightLines = rightLines
        self.hunks = hunks
        self.rows = rows
    }

    var differenceCount: Int { hunks.count }

    static func lines(in text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var normalized = text
        if normalized.utf8.contains(13) {
            normalized = (normalized as NSString).replacingOccurrences(of: "\r\n", with: "\n")
            normalized = (normalized as NSString).replacingOccurrences(of: "\r", with: "\n")
        }
        var lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if normalized.hasSuffix("\n") {
            lines.removeLast()
        }
        return lines
    }

    private static func normalized(_ line: String) -> String {
        line.filter { !$0.isWhitespace }
    }
}
