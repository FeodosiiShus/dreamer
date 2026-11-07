import Testing
import Foundation
@testable import Dreamder

private typealias Support = DiffEngineTestSupport

private func check(
    _ before: String,
    _ after: String,
    squash: Bool = false,
    trim: Bool = false,
    changes: PolicyExpectation<[DiffRange]>,
    policies: [ComparisonPolicy] = ComparisonPolicy.allCases
) throws {
    let text1 = Support.source(before)
    let text2 = Support.source(after)
    for policy in policies {
        let context = Comment(rawValue: "policy: \(policy), squash: \(squash), trim: \(trim), before: \(text1.debugDescription), after: \(text2.debugDescription)")
        let expected = changes.value(for: policy)
        #expect(expected != nil, context)

        var fragments = try ComparisonManager.compareLinesInner(text1, text2, policy: policy)
        verifyConsistency(fragments, text1: text1, text2: text2, context: Comment(rawValue: "compareLinesInner; \(context)"))

        fragments = ComparisonManager.processBlocks(fragments, text1: text1, text2: text2, policy: policy, squash: squash, trim: trim)
        verifyConsistency(fragments, text1: text1, text2: text2, context: Comment(rawValue: "processBlocks; \(context)"))

        if let expected {
            #expect(Support.lineRanges(fragments) == expected, context)
        }
    }
}

private func verifyConsistency(_ fragments: [LineFragment], text1: String, text2: String, context: Comment) {
    let starts1 = lineStartOffsets(text1)
    let starts2 = lineStartOffsets(text2)
    for fragment in fragments {
        #expect(fragment.startOffset1 <= fragment.endOffset1, context)
        #expect(fragment.startOffset2 <= fragment.endOffset2, context)
        #expect(fragment.startLine1 <= fragment.endLine1, context)
        #expect(fragment.startLine2 <= fragment.endLine2, context)
        #expect(fragment.startLine1 != fragment.endLine1 || fragment.startLine2 != fragment.endLine2, context)
        #expect(fragment.startLine1 >= 0, context)
        #expect(fragment.startLine2 >= 0, context)
        #expect(fragment.endLine1 <= starts1.count, context)
        #expect(fragment.endLine2 <= starts2.count, context)

        verifyLineOffsets(text1, starts: starts1, startLine: fragment.startLine1, endLine: fragment.endLine1,
                          startOffset: fragment.startOffset1, endOffset: fragment.endOffset1, context: context)
        verifyLineOffsets(text2, starts: starts2, startLine: fragment.startLine2, endLine: fragment.endLine2,
                          startOffset: fragment.startOffset2, endOffset: fragment.endOffset2, context: context)

        if let innerFragments = fragment.innerFragments {
            for inner in innerFragments {
                #expect(inner.startOffset1 <= inner.endOffset1, context)
                #expect(inner.startOffset2 <= inner.endOffset2, context)
                #expect(inner.startOffset1 != inner.endOffset1 || inner.startOffset2 != inner.endOffset2, context)
            }
        }
    }
}

private func lineStartOffsets(_ text: String) -> [Int] {
    var starts = [0]
    for (offset, unit) in text.utf16.enumerated() where unit == 0x0A {
        starts.append(offset + 1)
    }
    return starts
}

private func verifyLineOffsets(
    _ text: String,
    starts: [Int],
    startLine: Int,
    endLine: Int,
    startOffset: Int,
    endOffset: Int,
    context: Comment
) {
    guard startLine >= 0, startLine <= endLine, endLine <= starts.count else { return }
    let length = text.utf16.count
    if startLine != endLine {
        #expect(starts[startLine] == startOffset, context)
        let lastLine = endLine - 1
        var offset = lastLine + 1 < starts.count ? starts[lastLine + 1] - 1 : length
        if offset < length { offset += 1 }
        #expect(offset == endOffset, context)
    } else {
        let offset = startLine == starts.count ? length : starts[startLine]
        #expect(offset == startOffset, context)
        #expect(offset == endOffset, context)
    }
}

@Suite struct SplitComparisonTests {
    @Test func splitter() throws {
        try check("x", "z",
                  changes: .init(default: [Support.mod(0, 0, 1, 1)]))

        try check("x_y", "a_b",
                  changes: .init(default: [Support.mod(0, 0, 2, 2)]))

        try check("x_y", "a_b y",
                  changes: .init(default: [Support.mod(0, 0, 1, 1), Support.mod(1, 1, 1, 1)]))

        try check("x y", "x a_b y",
                  changes: .init(default: [Support.mod(0, 0, 1, 2)]))

        try check("x_y", "x a_y b",
                  changes: .init(default: [Support.mod(0, 0, 1, 1), Support.mod(1, 1, 1, 1)]))

        try check("x_", "x a_...",
                  changes: .init(default: [Support.mod(0, 0, 2, 2)]))

        try check("x_y_", "a_b_",
                  changes: .init(default: [Support.mod(0, 0, 2, 2)]))

        try check("x_y", " x _ y ",
                  changes: .init(default: [Support.mod(0, 0, 2, 2)]),
                  policies: [.default])

        try check("x_y", " x _ y.",
                  changes: .init(default: [Support.mod(0, 0, 1, 1), Support.mod(1, 1, 1, 1)]),
                  policies: [.default])

        try check("a_x_b_", " x_",
                  changes: .init(default: [Support.del(0, 0, 1), Support.mod(1, 0, 1, 1), Support.del(2, 1, 1)]),
                  policies: [.default])

        try check("a_x_b_", "!x_",
                  changes: .init(default: [Support.del(0, 0, 1), Support.mod(1, 0, 1, 1), Support.del(2, 1, 1)]))

        try check("< i", "<i<_i", trim: false,
                  changes: .init(default: [Support.mod(0, 0, 1, 2)]),
                  policies: [.default])

        try check(".l j", "U_._l j+", trim: false,
                  changes: .init(default: [Support.ins(0, 0, 2), Support.mod(0, 2, 1, 1)]),
                  policies: [.default])

        try check("      run();", "      //commentary_      while(run(true));",
                  changes: .init(default: [Support.mod(0, 0, 1, 2)]),
                  policies: [.default])
    }

    @Test func squash() throws {
        try check("x", "z", squash: true,
                  changes: .init(default: [Support.mod(0, 0, 1, 1)]))

        try check("x_y", "a_b", squash: true,
                  changes: .init(default: [Support.mod(0, 0, 2, 2)]))

        try check("x_y", "a_b y", squash: true,
                  changes: .init(default: [Support.mod(0, 0, 2, 2)]))

        try check("a_x_b_", " x_", squash: true,
                  changes: .init(default: [Support.mod(0, 0, 3, 1)]),
                  policies: [.default])

        try check("a_x_b_", "!x_", squash: true,
                  changes: .init(default: [Support.mod(0, 0, 3, 1)]))
    }

    @Test func trim() throws {
        try check("_", "     _    ", trim: true,
                  changes: .init(default: [Support.mod(0, 0, 2, 2)], trim: []))

        try check("", "     _    ", trim: true,
                  changes: .init(default: [Support.mod(0, 0, 1, 2)], trim: [Support.ins(1, 1, 1)], ignore: []))

        try check("     _    ", "", trim: true,
                  changes: .init(default: [Support.mod(0, 0, 2, 1)], trim: [Support.del(1, 1, 1)], ignore: []))

        try check("x_y", "z_ ", trim: true,
                  changes: .init(default: [Support.mod(0, 0, 2, 2)]))

        try check("z", "z_ ", trim: true,
                  changes: .init(default: [Support.ins(1, 1, 1)], ignore: []))

        try check("z_ x", "z_ w", trim: true,
                  changes: .init(default: [Support.mod(1, 1, 1, 1)]))

        try check("__z__", "z", trim: true,
                  changes: .init(default: [Support.del(0, 0, 2), Support.del(3, 1, 2)], ignore: []))
    }
}
