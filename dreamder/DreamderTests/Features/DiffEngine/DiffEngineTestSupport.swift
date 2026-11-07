import Foundation
@testable import Dreamder

struct PolicyExpectation<Value> {
    var `default`: Value?
    var trim: Value?
    var ignore: Value?

    func value(for policy: ComparisonPolicy) -> Value? {
        switch policy {
        case .ignoreWhitespaces: return ignore ?? trim ?? `default`
        case .trimWhitespaces: return trim ?? `default`
        case .default: return `default`
        }
    }
}

enum DiffEngineTestSupport {
    static func source(_ text: String) -> String {
        text.replacingOccurrences(of: "_", with: "\n")
    }

    static func mod(_ line1: Int, _ line2: Int, _ count1: Int, _ count2: Int) -> DiffRange {
        DiffRange(line1, line1 + count1, line2, line2 + count2)
    }

    static func del(_ line1: Int, _ line2: Int, _ count1: Int) -> DiffRange {
        DiffRange(line1, line1 + count1, line2, line2)
    }

    static func ins(_ line1: Int, _ line2: Int, _ count2: Int) -> DiffRange {
        DiffRange(line1, line1, line2, line2 + count2)
    }

    static func lineRanges(_ fragments: [LineFragment]) -> [DiffRange] {
        fragments.map { DiffRange($0.startLine1, $0.endLine1, $0.startLine2, $0.endLine2) }
    }

    static func offsetRanges(_ fragments: [DiffFragment]) -> [DiffRange] {
        fragments.map { DiffRange($0.startOffset1, $0.endOffset1, $0.startOffset2, $0.endOffset2) }
    }

    static func matchedPositions(_ marks: String) -> Set<Int> {
        var result: Set<Int> = []
        var position = 0
        for character in marks where character != "." {
            if character != " " { result.insert(position) }
            position += 1
        }
        return result
    }

    static func matchedLines(_ marks: String) -> Set<Int> {
        var result: Set<Int> = []
        var lineNumber = 0
        var current = ""
        func flush() {
            if current.contains(where: { $0 != " " && $0 != "_" }) {
                result.insert(lineNumber)
            }
            lineNumber += 1
            current = ""
        }
        for character in marks {
            current.append(character)
            if character == "_" || character == "*" {
                flush()
            }
        }
        if !current.isEmpty { flush() }
        return result
    }

    static func changedLines(_ fragments: [LineFragment], side: DiffSide) -> Set<Int> {
        var result: Set<Int> = []
        for fragment in fragments {
            let range = side == .left
                ? fragment.startLine1..<fragment.endLine1
                : fragment.startLine2..<fragment.endLine2
            result.formUnion(range)
        }
        return result
    }

    static func changedOffsets(_ fragments: [DiffFragment], side: DiffSide) -> Set<Int> {
        var result: Set<Int> = []
        for fragment in fragments {
            let range = side == .left
                ? fragment.startOffset1..<fragment.endOffset1
                : fragment.startOffset2..<fragment.endOffset2
            result.formUnion(range)
        }
        return result
    }

    static func changedOffsets(_ ranges: [MergeRange], side: ThreeSide) -> Set<Int> {
        var result: Set<Int> = []
        for range in ranges {
            result.formUnion(range.range(side))
        }
        return result
    }

    static func lines(_ text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    static func joined(_ lines: [String]) -> String {
        lines.joined(separator: "\n")
    }
}
