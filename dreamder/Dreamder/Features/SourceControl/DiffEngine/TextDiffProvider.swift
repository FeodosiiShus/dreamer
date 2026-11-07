import Foundation

nonisolated enum IgnorePolicy: Sendable, Hashable, CaseIterable {
    case `default`
    case trimWhitespaces
    case ignoreWhitespaces
    case ignoreWhitespacesChunks

    var comparisonPolicy: ComparisonPolicy {
        switch self {
        case .default: return .default
        case .trimWhitespaces: return .trimWhitespaces
        case .ignoreWhitespaces, .ignoreWhitespacesChunks: return .ignoreWhitespaces
        }
    }

    var isShouldSquash: Bool { true }

    var isShouldTrimChunks: Bool { self == .ignoreWhitespacesChunks }
}

nonisolated enum HighlightPolicy: Sendable, Hashable, CaseIterable {
    case byLine
    case byWord
    case byWordSplit
    case byChar
    case doNotHighlight

    var isShouldCompare: Bool { self != .doNotHighlight }

    var isShouldSquash: Bool { self != .byWordSplit }

    var fragmentsPolicy: InnerFragmentsPolicy {
        switch self {
        case .byWord, .byWordSplit: return .words
        case .byChar: return .chars
        case .byLine, .doNotHighlight: return .none
        }
    }
}

nonisolated enum TextDiffProvider {
    static func compare(
        _ text1: String,
        _ text2: String,
        ranges: [DiffRange],
        ignorePolicy: IgnorePolicy,
        highlightPolicy: HighlightPolicy
    ) throws -> [[LineFragment]]? {
        guard highlightPolicy.isShouldCompare else { return nil }

        let units1 = Array(text1.utf16)
        let units2 = Array(text2.utf16)
        let offsets1 = LineOffsets(text: units1)
        let offsets2 = LineOffsets(text: units2)

        let policy = ignorePolicy.comparisonPolicy
        let fragmentsPolicy = highlightPolicy.fragmentsPolicy
        let squash = highlightPolicy.isShouldSquash && ignorePolicy.isShouldSquash
        let trim = ignorePolicy.isShouldTrimChunks

        return try ranges.map { range in
            let fragments = try ComparisonManager.compareLinesInner(
                boundary: range,
                units1,
                units2,
                offsets1,
                offsets2,
                policy,
                fragmentsPolicy
            )
            return ComparisonManager.processBlocks(fragments, units1, units2, policy, squash: squash, trim: trim)
        }
    }
}
