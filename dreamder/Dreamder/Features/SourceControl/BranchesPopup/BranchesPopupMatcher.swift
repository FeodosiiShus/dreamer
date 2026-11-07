import Foundation

nonisolated enum BranchesPopupMatcher {
    static func matches(query: String, candidate: String) -> Bool {
        ranges(query: query, candidate: candidate) != nil
    }

    static func score(query: String, candidate: String) -> Int? {
        guard let indices = matchIndices(query: query, candidate: candidate) else { return nil }
        let characters = Array(candidate)
        var score = candidate.count
        for index in indices {
            if !isWordStart(characters, at: index) { score += 8 }
        }
        if let first = indices.first { score += first * 2 }
        return score
    }

    static func ranges(query: String, candidate: String) -> [Range<Int>]? {
        guard let indices = matchIndices(query: query, candidate: candidate) else { return nil }
        return contiguousRanges(indices)
    }

    static func isWordStart(_ characters: [Character], at index: Int) -> Bool {
        guard index > 0 else { return true }
        guard index < characters.count else { return false }
        let previous = characters[index - 1]
        let current = characters[index]
        guard current.isLetter || current.isNumber else { return false }
        guard previous.isLetter || previous.isNumber else { return true }
        if previous.isLowercase, current.isUppercase { return true }
        if previous.isNumber, current.isLetter { return true }
        if previous.isUppercase,
           current.isUppercase,
           index + 1 < characters.count,
           characters[index + 1].isLowercase {
            return true
        }
        return false
    }

    private static func matchIndices(query: String, candidate: String) -> [Int]? {
        let characters = Array(candidate)
        let parts = query
            .trimmingCharacters(in: .whitespaces)
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard !parts.isEmpty else { return [] }
        var indices: [Int] = []
        var searchStart = 0
        for part in parts {
            guard let matched = bestMatch(
                pattern: Array(part.lowercased()),
                characters: characters,
                from: searchStart
            ) else {
                return nil
            }
            indices.append(contentsOf: matched.indices)
            searchStart = matched.end
        }
        return indices
    }

    nonisolated private struct Match {
        let indices: [Int]
        let score: Int
        let end: Int
    }

    private static func bestMatch(
        pattern: [Character],
        characters: [Character],
        from start: Int
    ) -> Match? {
        guard let firstCharacter = pattern.first else { return Match(indices: [], score: 0, end: start) }
        var best: Match?
        var candidateIndex = max(start, 0)
        while candidateIndex < characters.count {
            guard equals(characters[candidateIndex], firstCharacter) else {
                candidateIndex += 1
                continue
            }
            if let match = greedyMatch(pattern: pattern, characters: characters, start: candidateIndex),
               match.score < (best?.score ?? .max) {
                best = match
            }
            candidateIndex += 1
        }
        return best
    }

    private static func greedyMatch(
        pattern: [Character],
        characters: [Character],
        start: Int
    ) -> Match? {
        var indices = [start]
        var index = start
        for character in pattern.dropFirst() {
            var nextIndex = index + 1
            var found: Int?
            while nextIndex < characters.count {
                if equals(characters[nextIndex], character) {
                    found = nextIndex
                    break
                }
                nextIndex += 1
            }
            guard let found else { return nil }
            indices.append(found)
            index = found
        }
        guard let first = indices.first, let last = indices.last else { return nil }
        var score = first * 4 + (last - first)
        for position in indices where !isWordStart(characters, at: position) {
            score += 6
        }
        return Match(indices: indices, score: score, end: last + 1)
    }

    private static func contiguousRanges(_ indices: [Int]) -> [Range<Int>] {
        guard let first = indices.first else { return [] }
        var ranges: [Range<Int>] = []
        var start = first
        var previous = first
        for index in indices.dropFirst() {
            if index == previous + 1 {
                previous = index
                continue
            }
            ranges.append(start..<(previous + 1))
            start = index
            previous = index
        }
        ranges.append(start..<(previous + 1))
        return ranges
    }

    private static func equals(_ lhs: Character, _ rhs: Character) -> Bool {
        lhs == rhs || String(lhs).lowercased() == String(rhs).lowercased()
    }
}
