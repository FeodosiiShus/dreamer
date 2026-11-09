import Foundation

nonisolated enum DetectedIndent: Equatable, Sendable {
    case tabs
    case spaces(size: Int?)
}

nonisolated enum IndentDetector {
    static let minimumLineCount = 3
    static let maximumDetectableByteCount = 1_048_576
    static let rateThreshold = 0.8
    static let maximumIndentToDetect = 8

    private static let tab: UInt8 = 9
    private static let space: UInt8 = 32
    private static let lineFeed: UInt8 = 10
    private static let carriageReturn: UInt8 = 13
    private static let asterisk: UInt8 = 42
    private static let slash: UInt8 = 47

    private enum LineIndent: Equatable {
        case ignored
        case tabs
        case spaces(Int)
    }

    static func detect(in text: String) -> DetectedIndent? {
        let bytes = text.utf8
        guard bytes.count <= maximumDetectableByteCount else { return nil }
        let lines = bytes.split(separator: lineFeed, omittingEmptySubsequences: false)
        guard lines.count >= minimumLineCount else { return nil }
        var statistics = IndentUsageStatistics()
        for line in lines {
            switch classify(line) {
            case .ignored:
                continue
            case .tabs:
                statistics.addLineWithTabs()
            case .spaces(let count):
                statistics.addLineWithSpaces(indent: count)
            }
        }
        return adjust(statistics)
    }

    private static func classify(_ line: Substring.UTF8View) -> LineIndent {
        var spaces = 0
        var hasTab = false
        var index = line.startIndex
        while index < line.endIndex {
            let byte = line[index]
            if byte == space {
                spaces += 1
            } else if byte == tab {
                hasTab = true
            } else {
                break
            }
            index = line.index(after: index)
        }
        guard index < line.endIndex else { return .ignored }
        let first = line[index]
        if first == carriageReturn {
            return .ignored
        }
        if hasTab {
            return .tabs
        }
        if isCommentStart(first, in: line, at: index) {
            return .ignored
        }
        return .spaces(spaces)
    }

    private static func isCommentStart(
        _ first: UInt8,
        in line: Substring.UTF8View,
        at index: Substring.UTF8View.Index
    ) -> Bool {
        if first == asterisk {
            return true
        }
        guard first == slash else { return false }
        let next = line.index(after: index)
        guard next < line.endIndex else { return false }
        return line[next] == slash || line[next] == asterisk
    }

    private static func adjust(_ statistics: IndentUsageStatistics) -> DetectedIndent? {
        let tabLines = statistics.totalLinesWithLeadingTabs
        let spaceLines = statistics.totalLinesWithLeadingSpaces
        let isTabsUsed = tabLines > spaceLines
        let total = spaceLines + tabLines
        let isSpacesUsed = total > 0 && Double(spaceLines) / Double(total) > rateThreshold
        if isTabsUsed {
            return .tabs
        }
        guard isSpacesUsed else { return nil }
        let size = positiveIndentSize(statistics)
        return .spaces(size: size > 0 ? size : nil)
    }

    static func positiveIndentSize(_ statistics: IndentUsageStatistics) -> Int {
        let usages = statistics.sortedUsages
        guard !usages.isEmpty else { return -1 }
        var mostUsed = usages[0]
        if mostUsed.indent == 0 {
            guard usages.count >= 2 else { return -1 }
            mostUsed = usages[1]
        }
        guard mostUsed.indent <= maximumIndentToDetect else { return -1 }
        let rate = Double(mostUsed.timesUsed) / Double(statistics.totalLinesWithLeadingSpaces)
        return rate > rateThreshold ? mostUsed.indent : -1
    }
}

nonisolated struct IndentUsageStatistics: Sendable {
    struct Usage: Equatable, Sendable {
        let indent: Int
        let timesUsed: Int
    }

    private struct ParentIndent {
        let indent: Int
        let relativeIndent: Int
    }

    private(set) var totalLinesWithLeadingTabs = 0
    private(set) var totalLinesWithLeadingSpaces = 0
    private var usages: [Int: Int] = [:]
    private var parents = [ParentIndent(indent: 0, relativeIndent: 0)]
    private var previousIndent = 0
    private var previousRelativeIndent = 0

    var sortedUsages: [Usage] {
        usages
            .map { Usage(indent: $0.key, timesUsed: $0.value) }
            .sorted { lhs, rhs in
                lhs.timesUsed == rhs.timesUsed ? lhs.indent > rhs.indent : lhs.timesUsed > rhs.timesUsed
            }
    }

    mutating func addLineWithTabs() {
        totalLinesWithLeadingTabs += 1
    }

    mutating func addLineWithSpaces(indent currentIndent: Int) {
        var relativeIndent = currentIndent - previousIndent
        if relativeIndent < 0 {
            let parent = findParent(of: currentIndent)
            previousIndent = parent.indent
            previousRelativeIndent = parent.relativeIndent
            relativeIndent = currentIndent - previousIndent
        }
        if relativeIndent == 0 {
            relativeIndent = previousRelativeIndent
        } else {
            parents.append(ParentIndent(indent: currentIndent, relativeIndent: relativeIndent))
        }
        usages[relativeIndent, default: 0] += 1
        previousRelativeIndent = relativeIndent
        previousIndent = currentIndent
        if currentIndent > 0 {
            totalLinesWithLeadingSpaces += 1
        }
    }

    private mutating func findParent(of indent: Int) -> ParentIndent {
        while parents.count != 1, let last = parents.last, last.indent > indent {
            parents.removeLast()
        }
        return parents[parents.count - 1]
    }
}
