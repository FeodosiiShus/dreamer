import Foundation

nonisolated struct LineMergeBlock: Sendable, Hashable {
    let range: MergeRange
    let type: MergeConflictType
    let resolvedLines: [String]?
}

nonisolated enum InnerFragmentsPolicy: Sendable, Hashable {
    case none
    case words
    case chars
}

nonisolated struct LineFragment: Sendable, Hashable {
    let startLine1: Int
    let endLine1: Int
    let startLine2: Int
    let endLine2: Int
    let startOffset1: Int
    let endOffset1: Int
    let startOffset2: Int
    let endOffset2: Int
    let innerFragments: [DiffFragment]?

    init(
        startLine1: Int,
        endLine1: Int,
        startLine2: Int,
        endLine2: Int,
        startOffset1: Int,
        endOffset1: Int,
        startOffset2: Int,
        endOffset2: Int,
        innerFragments: [DiffFragment]? = nil
    ) {
        self.startLine1 = startLine1
        self.endLine1 = endLine1
        self.startLine2 = startLine2
        self.endLine2 = endLine2
        self.startOffset1 = startOffset1
        self.endOffset1 = endOffset1
        self.startOffset2 = startOffset2
        self.endOffset2 = endOffset2
        self.innerFragments = Self.droppingWholeChanged(
            innerFragments,
            length1: endOffset1 - startOffset1,
            length2: endOffset2 - startOffset2
        )
    }

    init(_ fragment: LineFragment, innerFragments: [DiffFragment]?) {
        self.init(
            startLine1: fragment.startLine1,
            endLine1: fragment.endLine1,
            startLine2: fragment.startLine2,
            endLine2: fragment.endLine2,
            startOffset1: fragment.startOffset1,
            endOffset1: fragment.endOffset1,
            startOffset2: fragment.startOffset2,
            endOffset2: fragment.endOffset2,
            innerFragments: innerFragments
        )
    }

    private static func droppingWholeChanged(_ fragments: [DiffFragment]?, length1: Int, length2: Int) -> [DiffFragment]? {
        if let fragments, fragments.count == 1, let only = fragments.first {
            if only.startOffset1 == 0 && only.startOffset2 == 0 && only.endOffset1 == length1 && only.endOffset2 == length2 {
                return nil
            }
        }
        return fragments
    }
}

nonisolated enum ComparisonManager {
    static func compareLineRanges(_ lines1: [String], _ lines2: [String], policy: ComparisonPolicy = .default) throws -> [DiffRange] {
        try Task.checkCancellation()
        let units1 = lines1.map { Array($0.utf16) }
        let units2 = lines2.map { Array($0.utf16) }
        return try ByLine.compare(units1, units2, policy).changes
    }

    static func compareLines(_ text1: String, _ text2: String, policy: ComparisonPolicy = .default) throws -> [LineFragment] {
        try compareLines(Array(text1.utf16), Array(text2.utf16), policy)
    }

    static func compareLinesInner(
        _ text1: String,
        _ text2: String,
        policy: ComparisonPolicy = .default,
        fragmentsPolicy: InnerFragmentsPolicy = .words
    ) throws -> [LineFragment] {
        let units1 = Array(text1.utf16)
        let units2 = Array(text2.utf16)
        let lineFragments = try compareLines(units1, units2, policy)
        guard fragmentsPolicy != .none else { return lineFragments }
        return try createInnerFragments(lineFragments, units1, units2, policy, fragmentsPolicy)
    }

    static func compareLines(
        _ text1: String,
        _ text2: String,
        _ text3: String,
        policy: ComparisonPolicy = .default
    ) throws -> [MergeRange] {
        try ByLine.compare(lineContents(text1), lineContents(text2), lineContents(text3), policy)
    }

    static func mergeLines(
        _ text1: String,
        _ text2: String,
        _ text3: String,
        policy: ComparisonPolicy = .default
    ) throws -> [MergeRange] {
        try ByLine.merge(lineContents(text1), lineContents(text2), lineContents(text3), policy)
    }

    static func mergeLines(
        left: [String],
        base: [String],
        right: [String],
        policy: ComparisonPolicy = .default
    ) throws -> [MergeRange] {
        try ByLine.merge(
            left.map { Array($0.utf16) },
            base.map { Array($0.utf16) },
            right.map { Array($0.utf16) },
            policy
        )
    }

    static func mergeBlocks(
        left: [String],
        base: [String],
        right: [String],
        policy: ComparisonPolicy = .default
    ) throws -> [LineMergeBlock] {
        let leftUnits = left.map { Array($0.utf16) }
        let baseUnits = base.map { Array($0.utf16) }
        let rightUnits = right.map { Array($0.utf16) }
        let ranges = try ByLine.merge(leftUnits, baseUnits, rightUnits, policy)
        return mergeBlocks(ranges: ranges, left: leftUnits, base: baseUnits, right: rightUnits, policy: policy)
    }

    static func mergeBlocks(
        ranges: [MergeRange],
        left: [DiffUnits],
        base: [DiffUnits],
        right: [DiffUnits],
        policy: ComparisonPolicy
    ) -> [LineMergeBlock] {
        ranges.map { range in
            let type = MergeRangeUtil.lineMergeType(range: range, left: left, base: base, right: right, policy: policy)
            var resolvedLines: [String]?
            if type.kind == .conflict && type.canBeResolved {
                let resolved = MergeResolveUtil.tryResolve(
                    left: MergeRangeUtil.joinedLines(left, range.range(.left)),
                    base: MergeRangeUtil.joinedLines(base, range.range(.base)),
                    right: MergeRangeUtil.joinedLines(right, range.range(.right))
                )
                if let resolved {
                    let text = String(decoding: resolved, as: UTF16.self)
                    resolvedLines = text.isEmpty
                        ? [""]
                        : text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
                }
            }
            return LineMergeBlock(range: range, type: type, resolvedLines: resolvedLines)
        }
    }

    static func compareWords(_ text1: String, _ text2: String, policy: ComparisonPolicy = .default) throws -> [DiffFragment] {
        try ByWord.compare(Array(text1.utf16), Array(text2.utf16), policy)
    }

    static func compareWords(
        _ text1: String,
        _ text2: String,
        _ text3: String,
        policy: ComparisonPolicy = .default
    ) throws -> [MergeRange] {
        try ByWord.compare(Array(text1.utf16), Array(text2.utf16), Array(text3.utf16), policy)
    }

    static func compareChars(_ text1: String, _ text2: String, policy: ComparisonPolicy = .default) throws -> [DiffFragment] {
        try compareChars(Array(text1.utf16), Array(text2.utf16), policy)
    }

    static func isEquals(_ text1: String, _ text2: String, policy: ComparisonPolicy) -> Bool {
        ComparisonUtil.isEqualTexts(Array(text1.utf16), Array(text2.utf16), policy)
    }

    static func tryResolveConflict(left: String, base: String, right: String) -> String? {
        MergeResolveUtil.tryResolve(left: left, base: base, right: right)
    }

    static func mergeType(
        range: MergeRange,
        left: [String],
        base: [String],
        right: [String],
        policy: ComparisonPolicy = .default
    ) -> MergeConflictType {
        MergeRangeUtil.lineMergeType(
            range: range,
            left: left.map { Array($0.utf16) },
            base: base.map { Array($0.utf16) },
            right: right.map { Array($0.utf16) },
            policy: policy
        )
    }

    static func lineContents(_ text: String) -> [DiffUnits] {
        let units = Array(text.utf16)
        return LineOffsets(text: units).lineContents(in: units)
    }

    static func compareLines(_ text1: DiffUnits, _ text2: DiffUnits, _ policy: ComparisonPolicy) throws -> [LineFragment] {
        let offsets1 = LineOffsets(text: text1)
        let offsets2 = LineOffsets(text: text2)
        let iterable = try ByLine.compare(offsets1.lineContents(in: text1), offsets2.lineContents(in: text2), policy)
        return convertIntoLineFragments(offsets1, offsets2, iterable)
    }

    static func compareChars(_ text1: DiffUnits, _ text2: DiffUnits, _ policy: ComparisonPolicy) throws -> [DiffFragment] {
        let iterable: DiffChanges
        switch policy {
        case .default:
            iterable = try ByChar.compareTwoStep(text1, text2)
        case .trimWhitespaces:
            iterable = try ByChar.compareTrimWhitespaces(text1, text2)
        case .ignoreWhitespaces:
            iterable = try ByChar.compareIgnoreWhitespaces(text1, text2)
        }
        return ByWord.convertIntoDiffFragments(iterable)
    }

    static func convertIntoLineFragments(_ offsets1: LineOffsets, _ offsets2: LineOffsets, _ changes: DiffChanges) -> [LineFragment] {
        changes.changes.map { range in
            createLineFragment(range.start1, range.end1, range.start2, range.end2, offsets1, offsets2)
        }
    }

    static func createLineFragment(
        _ startLine1: Int,
        _ endLine1: Int,
        _ startLine2: Int,
        _ endLine2: Int,
        _ offsets1: LineOffsets,
        _ offsets2: LineOffsets
    ) -> LineFragment {
        let range1 = offsets(offsets1, startLine1, endLine1)
        let range2 = offsets(offsets2, startLine2, endLine2)
        return LineFragment(
            startLine1: startLine1,
            endLine1: endLine1,
            startLine2: startLine2,
            endLine2: endLine2,
            startOffset1: range1.start,
            endOffset1: range1.end,
            startOffset2: range2.start,
            endOffset2: range2.end
        )
    }

    private static func offsets(_ lineOffsets: LineOffsets, _ startIndex: Int, _ endIndex: Int) -> (start: Int, end: Int) {
        if startIndex == endIndex {
            let offset: Int
            if startIndex < lineOffsets.lineCount {
                offset = lineOffsets.lineStart(startIndex)
            } else {
                offset = lineOffsets.lineCount == 0 ? 0 : lineOffsets.lineEnd(lineOffsets.lineCount - 1, includeNewline: true)
            }
            return (offset, offset)
        }
        return (lineOffsets.lineStart(startIndex), lineOffsets.lineEnd(endIndex - 1, includeNewline: true))
    }

    static func createInnerFragments(
        _ lineFragments: [LineFragment],
        _ text1: DiffUnits,
        _ text2: DiffUnits,
        _ policy: ComparisonPolicy,
        _ fragmentsPolicy: InnerFragmentsPolicy
    ) throws -> [LineFragment] {
        var result: [LineFragment] = []
        result.reserveCapacity(lineFragments.count)

        var tooBigChunksCount = 0
        for fragment in lineFragments {
            try Task.checkCancellation()
            do {
                let tryComputeDifferences = tooBigChunksCount < ComparisonUtil.maxBadLines
                result.append(contentsOf: try createInnerFragments(
                    fragment,
                    text1,
                    text2,
                    policy,
                    fragmentsPolicy,
                    tryComputeDifferences: tryComputeDifferences
                ))
            } catch is DiffTooBigError {
                result.append(fragment)
                tooBigChunksCount += 1
            }
        }
        return result
    }

    private static func createInnerFragments(
        _ fragment: LineFragment,
        _ text1: DiffUnits,
        _ text2: DiffUnits,
        _ policy: ComparisonPolicy,
        _ fragmentsPolicy: InnerFragmentsPolicy,
        tryComputeDifferences: Bool
    ) throws -> [LineFragment] {
        if fragmentsPolicy == .none { return [fragment] }

        let subSequence1 = Array(text1[fragment.startOffset1..<fragment.endOffset1])
        let subSequence2 = Array(text2[fragment.startOffset2..<fragment.endOffset2])

        if fragment.startLine1 == fragment.endLine1 || fragment.startLine2 == fragment.endLine2 {
            if ComparisonUtil.isEqualTexts(subSequence1, subSequence2, policy) {
                return [LineFragment(fragment, innerFragments: [])]
            }
            return [fragment]
        }

        if !tryComputeDifferences { return [fragment] }

        if fragmentsPolicy == .chars {
            let innerChanges = try compareChars(subSequence1, subSequence2, policy)
            return [LineFragment(fragment, innerFragments: innerChanges)]
        }
        return try createInnerWordFragments(fragment, subSequence1, subSequence2, policy)
    }

    private static func createInnerWordFragments(
        _ fragment: LineFragment,
        _ subSequence1: DiffUnits,
        _ subSequence2: DiffUnits,
        _ policy: ComparisonPolicy
    ) throws -> [LineFragment] {
        let lineBlocks = try ByWord.compareAndSplit(subSequence1, subSequence2, policy)
        if lineBlocks.isEmpty { return [fragment] }

        let startOffset1 = fragment.startOffset1
        let startOffset2 = fragment.startOffset2

        var currentStartLine1 = fragment.startLine1
        var currentStartLine2 = fragment.startLine2

        var chunks: [LineFragment] = []
        for (index, block) in lineBlocks.enumerated() {
            let offsets = block.offsets
            let isLast = index == lineBlocks.count - 1
            let currentEndLine1 = isLast ? fragment.endLine1 : currentStartLine1 + block.newlines1
            let currentEndLine2 = isLast ? fragment.endLine2 : currentStartLine2 + block.newlines2

            chunks.append(LineFragment(
                startLine1: currentStartLine1,
                endLine1: currentEndLine1,
                startLine2: currentStartLine2,
                endLine2: currentEndLine2,
                startOffset1: offsets.start1 + startOffset1,
                endOffset1: offsets.end1 + startOffset1,
                startOffset2: offsets.start2 + startOffset2,
                endOffset2: offsets.end2 + startOffset2,
                innerFragments: block.fragments
            ))

            currentStartLine1 = currentEndLine1
            currentStartLine2 = currentEndLine2
        }
        return chunks
    }

    static func squash(_ oldFragments: [LineFragment]) -> [LineFragment] {
        if oldFragments.isEmpty { return oldFragments }
        var newFragments: [LineFragment] = []
        for group in adjoiningGroups(oldFragments) {
            newFragments.append(doSquash(group))
        }
        return newFragments
    }

    static func processBlocks(
        _ oldFragments: [LineFragment],
        text1: String,
        text2: String,
        policy: ComparisonPolicy,
        squash: Bool,
        trim: Bool
    ) -> [LineFragment] {
        processBlocks(oldFragments, Array(text1.utf16), Array(text2.utf16), policy, squash: squash, trim: trim)
    }

    static func processBlocks(
        _ oldFragments: [LineFragment],
        _ text1: DiffUnits,
        _ text2: DiffUnits,
        _ policy: ComparisonPolicy,
        squash: Bool,
        trim: Bool
    ) -> [LineFragment] {
        if !squash && !trim { return oldFragments }
        if oldFragments.isEmpty { return oldFragments }

        var newFragments: [LineFragment] = []
        for group in adjoiningGroups(oldFragments) {
            newFragments.append(contentsOf: processAdjoining(group, text1, text2, policy, squash: squash, trim: trim))
        }
        return newFragments
    }

    private static func adjoiningGroups(_ fragments: [LineFragment]) -> [[LineFragment]] {
        var groups: [[LineFragment]] = []
        var startIndex = 0
        for index in 1..<max(fragments.count, 1) where !isAdjoining(fragments[index - 1], fragments[index]) {
            groups.append(Array(fragments[startIndex..<index]))
            startIndex = index
        }
        if startIndex < fragments.count {
            groups.append(Array(fragments[startIndex...]))
        }
        return groups
    }

    private static func processAdjoining(
        _ fragments: [LineFragment],
        _ text1: DiffUnits,
        _ text2: DiffUnits,
        _ policy: ComparisonPolicy,
        squash: Bool,
        trim: Bool
    ) -> [LineFragment] {
        var start = 0
        var end = fragments.count

        if trim && policy == .ignoreWhitespaces {
            while start < end {
                if isSignificantUnderIgnoreWhitespaces(fragments[start], text1, text2) { break }
                start += 1
            }
            while start < end {
                if isSignificantUnderIgnoreWhitespaces(fragments[end - 1], text1, text2) { break }
                end -= 1
            }
        }

        if start == end { return [] }
        if squash {
            return [doSquash(Array(fragments[start..<end]))]
        }
        return Array(fragments[start..<end])
    }

    private static func isSignificantUnderIgnoreWhitespaces(_ fragment: LineFragment, _ text1: DiffUnits, _ text2: DiffUnits) -> Bool {
        let sequence1 = Array(text1[fragment.startOffset1..<fragment.endOffset1])
        let sequence2 = Array(text2[fragment.startOffset2..<fragment.endOffset2])
        let hasInnerChanges = fragment.innerFragments.map { !$0.isEmpty } ?? true
        return hasInnerChanges && !ComparisonUtil.equalsIgnoreWhitespaces(sequence1, sequence2)
    }

    private static func doSquash(_ oldFragments: [LineFragment]) -> LineFragment {
        let firstFragment = oldFragments[0]
        let lastFragment = oldFragments[oldFragments.count - 1]
        if oldFragments.count == 1 { return firstFragment }

        var newInnerFragments: [DiffFragment] = []
        for fragment in oldFragments {
            for innerFragment in extractInnerFragments(fragment) {
                let shift1 = fragment.startOffset1 - firstFragment.startOffset1
                let shift2 = fragment.startOffset2 - firstFragment.startOffset2

                if let previous = newInnerFragments.last, isAdjoiningInner(previous, innerFragment, shift1, shift2) {
                    newInnerFragments.removeLast()
                    newInnerFragments.append(DiffFragment(
                        previous.startOffset1,
                        innerFragment.endOffset1 + shift1,
                        previous.startOffset2,
                        innerFragment.endOffset2 + shift2
                    ))
                } else {
                    newInnerFragments.append(DiffFragment(
                        innerFragment.startOffset1 + shift1,
                        innerFragment.endOffset1 + shift1,
                        innerFragment.startOffset2 + shift2,
                        innerFragment.endOffset2 + shift2
                    ))
                }
            }
        }

        return LineFragment(
            startLine1: firstFragment.startLine1,
            endLine1: lastFragment.endLine1,
            startLine2: firstFragment.startLine2,
            endLine2: lastFragment.endLine2,
            startOffset1: firstFragment.startOffset1,
            endOffset1: lastFragment.endOffset1,
            startOffset2: firstFragment.startOffset2,
            endOffset2: lastFragment.endOffset2,
            innerFragments: newInnerFragments
        )
    }

    private static func isAdjoining(_ before: LineFragment, _ after: LineFragment) -> Bool {
        before.endLine1 == after.startLine1
            && before.endLine2 == after.startLine2
            && before.endOffset1 == after.startOffset1
            && before.endOffset2 == after.startOffset2
    }

    private static func isAdjoiningInner(_ before: DiffFragment, _ after: DiffFragment, _ shift1: Int, _ shift2: Int) -> Bool {
        before.endOffset1 == after.startOffset1 + shift1 && before.endOffset2 == after.startOffset2 + shift2
    }

    private static func extractInnerFragments(_ lineFragment: LineFragment) -> [DiffFragment] {
        if let inner = lineFragment.innerFragments { return inner }
        let length1 = lineFragment.endOffset1 - lineFragment.startOffset1
        let length2 = lineFragment.endOffset2 - lineFragment.startOffset2
        return [DiffFragment(0, length1, 0, length2)]
    }
}
