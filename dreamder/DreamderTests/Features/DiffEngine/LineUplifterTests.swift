import Testing
import Foundation
@testable import Dreamder

private let chGun = "\u{1F52B}"

private struct UplifterDocument {
    let textLength: Int
    let lineStarts: [Int]

    init(_ text: String) {
        var starts = [0]
        var offset = 0
        for unit in text.utf16 {
            offset += 1
            if unit == 10 { starts.append(offset) }
        }
        textLength = offset
        lineStarts = starts
    }

    var lineCount: Int { lineStarts.count }

    func lineStartOffset(_ line: Int) -> Int? {
        lineStarts.indices.contains(line) ? lineStarts[line] : nil
    }

    func lineEndOffset(_ line: Int) -> Int? {
        guard lineStarts.indices.contains(line) else { return nil }
        return line + 1 < lineStarts.count ? lineStarts[line + 1] - 1 : textLength
    }
}

private func checkLineOffsets(
    _ document: UplifterDocument,
    startLine: Int,
    endLine: Int,
    startOffset: Int,
    endOffset: Int,
    _ context: Comment
) {
    if startLine != endLine {
        #expect(document.lineStartOffset(startLine) == startOffset, context)
        if var offset = document.lineEndOffset(endLine - 1) {
            if offset < document.textLength { offset += 1 }
            #expect(offset == endOffset, context)
        } else {
            Issue.record(context)
        }
    } else {
        let offset: Int? = startLine == document.lineCount ? document.textLength : document.lineStartOffset(startLine)
        #expect(offset == startOffset, context)
        #expect(offset == endOffset, context)
    }
}

private func checkInnerConsistency(_ fragments: [DiffFragment], _ context: Comment) {
    for fragment in fragments {
        #expect(fragment.startOffset1 <= fragment.endOffset1, context)
        #expect(fragment.startOffset2 <= fragment.endOffset2, context)
        #expect(fragment.startOffset1 != fragment.endOffset1 || fragment.startOffset2 != fragment.endOffset2, context)
    }
}

private func checkConsistency(_ fragments: [LineFragment], _ text1: String, _ text2: String, _ context: Comment) {
    let before = UplifterDocument(text1)
    let after = UplifterDocument(text2)
    for fragment in fragments {
        #expect(fragment.startOffset1 <= fragment.endOffset1, context)
        #expect(fragment.startOffset2 <= fragment.endOffset2, context)
        #expect(fragment.startLine1 <= fragment.endLine1, context)
        #expect(fragment.startLine2 <= fragment.endLine2, context)
        #expect(fragment.startLine1 != fragment.endLine1 || fragment.startLine2 != fragment.endLine2, context)
        #expect(fragment.startLine1 >= 0, context)
        #expect(fragment.startLine2 >= 0, context)
        #expect(fragment.endLine1 <= before.lineCount, context)
        #expect(fragment.endLine2 <= after.lineCount, context)
        checkLineOffsets(
            before,
            startLine: fragment.startLine1,
            endLine: fragment.endLine1,
            startOffset: fragment.startOffset1,
            endOffset: fragment.endOffset1,
            context
        )
        checkLineOffsets(
            after,
            startLine: fragment.startLine2,
            endLine: fragment.endLine2,
            startOffset: fragment.startOffset2,
            endOffset: fragment.endOffset2,
            context
        )
        checkInnerConsistency(fragment.innerFragments ?? [], context)
    }
}

private func parseUplifterSource(_ string: String) -> String {
    var result = string.replacingOccurrences(of: "_", with: "\n")
    for marker in ["[", "|", "]", ">"] {
        result = result.replacingOccurrences(of: marker, with: "")
    }
    return result
}

private func parseUplifterLineRanges(_ string: String) -> [(start: Int, end: Int)] {
    var result: [(start: Int, end: Int)] = []
    var line = 0
    var start = -1
    for scalar in string.unicodeScalars {
        switch scalar {
        case "[":
            start = line
        case "]":
            result.append((start, line + 1))
            start = -1
        case "|":
            result.append((line, line))
            start = -1
        case ">":
            result.append((line + 1, line + 1))
            start = -1
        case "_", "\n":
            line += 1
        default:
            break
        }
    }
    return result
}

private func parseExpectedRanges(_ input1: String, _ input2: String) -> [DiffRange] {
    let lines1 = parseUplifterLineRanges(input1)
    let lines2 = parseUplifterLineRanges(input2)
    #expect(lines1.count == lines2.count)
    return zip(lines1, lines2).map { DiffRange($0.start, $0.end, $1.start, $1.end) }
}

private func wordFirst(
    _ input1: String,
    _ input2: String,
    policy: ComparisonPolicy = .default
) throws {
    let text1 = parseUplifterSource(input1)
    let text2 = parseUplifterSource(input2)
    let expected = parseExpectedRanges(input1, input2)
    let context = Comment(rawValue: "policy: \(policy), before: \(input1.debugDescription), after: \(input2.debugDescription)")

    let units1 = Array(text1.utf16)
    let units2 = Array(text2.utf16)
    let fragments = try ComparisonManager.compareLinesWordFirst(
        units1,
        units2,
        LineOffsets(text: units1),
        LineOffsets(text: units2),
        policy
    )
    checkConsistency(fragments, text1, text2, context)

    #expect(DiffEngineTestSupport.lineRanges(fragments) == expected, context)
}

@Suite struct LineUplifterTests {
    @Test func testSimpleCases() throws {
        try wordFirst("", "")

        try wordFirst("X_[Y]_Z", "X_[A_B]_Z")

        try wordFirst("X_[Y]_Z", "X_|Z")
    }

    @Test func testTrickyEdgeCases() throws {
        try wordFirst("_[x]", "_[x ]")

        try wordFirst(
            "[a\n\(chGun)]\n|\(chGun)\(chGun)>",
            "[b]\n[]\n\(chGun)\(chGun)\n[\n!]")

        try wordFirst(
            "X_|_*_Z",
            "X_[Y]__*_Z")

        try wordFirst(
            "|X_",
            "[Y_Y]_X_")
    }
}
