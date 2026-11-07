import Foundation

nonisolated struct BranchesPopupMatcher: Sendable {
    static let matchOffsetWeight = 10000

    private let matcher: MinusculeMatcher

    init?(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "/" else { return nil }
        matcher = MinusculeMatcher(pattern: "*" + trimmed, mode: .ignoreCase)
    }

    func matches(_ name: String) -> Bool {
        matcher.match(name) != nil
    }

    func weight(_ name: String) -> Int? {
        guard let result = matcher.matchWithDegree(name) else { return nil }
        guard let start = result.fragments.first?.lowerBound else { return result.degree }
        return result.degree + Self.matchOffsetWeight - start
    }

    func ranges(_ name: String) -> [Range<Int>]? {
        guard let fragments = matcher.match(name) else { return nil }
        return Self.characterRanges(fragments, in: name)
    }

    private static func characterRanges(_ fragments: [Range<Int>], in name: String) -> [Range<Int>] {
        var characterIndexByUnit: [Int] = []
        for (index, character) in name.enumerated() {
            characterIndexByUnit.append(contentsOf: repeatElement(index, count: character.utf16.count))
        }
        return fragments.compactMap { fragment in
            guard fragment.lowerBound >= 0,
                  fragment.upperBound <= characterIndexByUnit.count,
                  !fragment.isEmpty else { return nil }
            return characterIndexByUnit[fragment.lowerBound]..<(characterIndexByUnit[fragment.upperBound - 1] + 1)
        }
    }
}
