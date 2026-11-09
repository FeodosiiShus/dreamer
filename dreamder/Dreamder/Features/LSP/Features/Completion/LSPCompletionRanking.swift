import Foundation

nonisolated struct LSPCompletionRankingInput: Sendable, Equatable {
    let filterText: String
    let label: String
    let sortText: String?
    let preselect: Bool
    let prefix: String
}

nonisolated enum LSPCompletionRanking {
    private struct Candidate {
        let index: Int
        let input: LSPCompletionRankingInput
        let degree: Int
    }

    static func order(_ inputs: [LSPCompletionRankingInput]) -> [Int] {
        var matchers: [String: MinusculeMatcher] = [:]
        var candidates: [Candidate] = []
        for (index, input) in inputs.enumerated() {
            guard !input.prefix.isEmpty else {
                candidates.append(Candidate(index: index, input: input, degree: 0))
                continue
            }
            let matcher: MinusculeMatcher
            if let cached = matchers[input.prefix] {
                matcher = cached
            } else {
                matcher = MinusculeMatcher(pattern: input.prefix, mode: .ignoreCase, fixKeyboardLayout: false)
                matchers[input.prefix] = matcher
            }
            guard let match = matcher.matchWithDegree(input.filterText) else { continue }
            candidates.append(Candidate(index: index, input: input, degree: match.degree))
        }
        candidates.sort(by: precedes)
        var ordered = candidates.map(\.index)
        if let preselected = candidates.firstIndex(where: \.input.preselect), preselected > 0 {
            ordered.insert(ordered.remove(at: preselected), at: 0)
        }
        return ordered
    }

    private static func precedes(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
        let lhsSort = lhs.input.sortText
        let rhsSort = rhs.input.sortText
        if (lhsSort == nil) != (rhsSort == nil) {
            return lhsSort != nil
        }
        if let lhsSort, let rhsSort, lhsSort != rhsSort {
            return lhsSort < rhsSort
        }
        if lhs.degree != rhs.degree {
            return lhs.degree > rhs.degree
        }
        if lhs.input.label != rhs.input.label {
            return lhs.input.label < rhs.input.label
        }
        return lhs.index < rhs.index
    }
}
