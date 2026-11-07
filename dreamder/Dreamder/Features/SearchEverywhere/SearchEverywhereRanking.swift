import Foundation

nonisolated struct SearchEverywhereWeightKey: Hashable, Comparable, Sendable {
    private static let matchID = "matchWeight"

    let id: String
    let order: Int
    let defaultWeight: Int

    static let match = SearchEverywhereWeightKey(validatedID: matchID, order: 0, defaultWeight: 0)
    static let recency = SearchEverywhereWeightKey(validatedID: "recency", order: 100, defaultWeight: 0)
    static let notDeprecated = SearchEverywhereWeightKey(validatedID: "notDeprecated", order: 200, defaultWeight: 1)

    init?(id: String, order: Int, defaultWeight: Int) {
        guard id == Self.matchID ? order == 0 : order > 0 else { return nil }
        self.init(validatedID: id, order: order, defaultWeight: defaultWeight)
    }

    private init(validatedID: String, order: Int, defaultWeight: Int) {
        self.id = validatedID
        self.order = order
        self.defaultWeight = defaultWeight
    }

    func compare(_ other: SearchEverywhereWeightKey) -> Int {
        if order != other.order {
            return order < other.order ? -1 : 1
        }
        if id.utf16.elementsEqual(other.id.utf16) {
            return 0
        }
        return id.utf16.lexicographicallyPrecedes(other.id.utf16) ? -1 : 1
    }

    static func == (lhs: SearchEverywhereWeightKey, rhs: SearchEverywhereWeightKey) -> Bool {
        lhs.order == rhs.order && lhs.id == rhs.id
    }

    static func < (lhs: SearchEverywhereWeightKey, rhs: SearchEverywhereWeightKey) -> Bool {
        lhs.compare(rhs) < 0
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(order)
    }
}

nonisolated struct SearchEverywhereWeightComponent: Hashable, Sendable {
    let key: SearchEverywhereWeightKey
    let weight: Int

    init(key: SearchEverywhereWeightKey, weight: Int) {
        self.key = key
        self.weight = weight
    }

    init(weight: Int) {
        self.init(key: .match, weight: weight)
    }
}

nonisolated struct SearchEverywhereComposedWeight: Comparable, Sendable {
    let components: [SearchEverywhereWeightComponent]

    var first: Int {
        components.first?.weight ?? SearchEverywhereWeightKey.match.defaultWeight
    }

    init(_ matchWeight: Int) {
        components = [SearchEverywhereWeightComponent(weight: matchWeight)]
    }

    init(match: Int, recency: Int) {
        components = [
            SearchEverywhereWeightComponent(weight: match),
            SearchEverywhereWeightComponent(key: .recency, weight: recency)
        ]
    }

    init?(components: [SearchEverywhereWeightComponent]) {
        let sorted = components.sorted { $0.key < $1.key }
        guard let head = sorted.first, head.key.order == 0 else { return nil }
        for index in sorted.indices.dropFirst() where !(sorted[index - 1].key < sorted[index].key) {
            return nil
        }
        self.components = sorted
    }

    private init(sortedComponents: [SearchEverywhereWeightComponent]) {
        components = sortedComponents
    }

    func with(_ component: SearchEverywhereWeightComponent) -> SearchEverywhereComposedWeight {
        let kept = components.filter { $0.key != component.key }
        return SearchEverywhereComposedWeight(sortedComponents: (kept + [component]).sorted { $0.key < $1.key })
    }

    func compare(_ other: SearchEverywhereComposedWeight) -> Int {
        let left = components
        let right = other.components
        var leftIndex = 0
        var rightIndex = 0

        while leftIndex < left.count || rightIndex < right.count {
            let keyOrder: Int
            if leftIndex == left.count {
                keyOrder = 1
            } else if rightIndex == right.count {
                keyOrder = -1
            } else {
                keyOrder = left[leftIndex].key.compare(right[rightIndex].key)
            }

            let result: Int
            if keyOrder < 0 {
                result = Self.sign(left[leftIndex].weight, left[leftIndex].key.defaultWeight)
                leftIndex += 1
            } else if keyOrder > 0 {
                result = Self.sign(right[rightIndex].key.defaultWeight, right[rightIndex].weight)
                rightIndex += 1
            } else {
                result = Self.sign(left[leftIndex].weight, right[rightIndex].weight)
                leftIndex += 1
                rightIndex += 1
            }

            if result != 0 { return result }
        }
        return 0
    }

    static func == (lhs: SearchEverywhereComposedWeight, rhs: SearchEverywhereComposedWeight) -> Bool {
        lhs.compare(rhs) == 0
    }

    static func < (lhs: SearchEverywhereComposedWeight, rhs: SearchEverywhereComposedWeight) -> Bool {
        lhs.compare(rhs) < 0
    }

    private static func sign(_ lhs: Int, _ rhs: Int) -> Int {
        lhs == rhs ? 0 : (lhs < rhs ? -1 : 1)
    }
}

nonisolated enum SearchEverywhereProvider: CaseIterable, Hashable, Sendable {
    case topHit
    case recentFiles
    case classes
    case files
    case symbols
    case runConfigurations
    case actions
    case nonIndexable
    case text

    var priority: Int {
        switch self {
        case .topHit: return 9950
        case .recentFiles: return 9930
        case .classes: return 9900
        case .files: return 9800
        case .symbols: return 9700
        case .runConfigurations: return 9650
        case .actions: return 9600
        case .nonIndexable: return 9000
        case .text: return 8500
        }
    }

    var keepsDiscoveryOrder: Bool {
        self == .text
    }
}

nonisolated extension SearchEverywhereSectionKind {
    var provider: SearchEverywhereProvider {
        switch self {
        case .recent: return .recentFiles
        case .files: return .files
        case .classes: return .classes
        case .symbols: return .symbols
        case .actions: return .actions
        case .text: return .text
        }
    }
}

nonisolated struct SearchEverywhereCandidate: Sendable {
    let id: String
    let provider: SearchEverywhereProvider
    let title: String
    let weight: SearchEverywhereComposedWeight
    let isExactMatch: Bool
    let equalityKey: String?
}

nonisolated struct SearchEverywhereRun<Element: Equatable & Sendable>: Sendable {
    let element: Element
    let range: Range<Int>
}

nonisolated enum SearchEverywhereRanking {
    static let exactMatchDegree = 15_000
    private static let exactMatchDegreeTolerance = 1_000

    static func shouldInsertAbove(
        newProviderPriority: Int,
        newIsExactMatch: Bool,
        newWeight: SearchEverywhereComposedWeight,
        itemProviderPriority: Int,
        itemIsExactMatch: Bool,
        itemWeight: SearchEverywhereComposedWeight,
        prioritizeExactMatch: Bool
    ) -> Bool {
        if newProviderPriority != itemProviderPriority {
            return newProviderPriority > itemProviderPriority
        }
        if prioritizeExactMatch && newIsExactMatch != itemIsExactMatch {
            return newIsExactMatch
        }
        return newWeight > itemWeight
    }

    static func isInExactMatchDegreeRange(_ degree: Int) -> Bool {
        degree >= exactMatchDegree - exactMatchDegreeTolerance
    }

    static func isExactMatch(
        isExactMatchFromItem: Bool,
        presentableText: String,
        inputQuery: String,
        isFile: Bool,
        inputQueryHasNoExtension: Bool,
        isDirectory: Bool
    ) -> Bool {
        if isExactMatchFromItem { return true }
        guard !isDirectory else { return false }
        if presentableText == inputQuery { return true }
        return isFile && inputQueryHasNoExtension && presentableText.hasPrefix(inputQuery + ".")
    }

    static func isExactMatch(degree: Int, presentableText: String, inputQuery: String, isFile: Bool) -> Bool {
        isExactMatch(
            isExactMatchFromItem: isInExactMatchDegreeRange(degree),
            presentableText: presentableText,
            inputQuery: inputQuery,
            isFile: isFile,
            inputQueryHasNoExtension: !inputQuery.contains("."),
            isDirectory: false
        )
    }

    static func deduplicated(_ candidates: [SearchEverywhereCandidate]) -> [Int] {
        var kept: [Int?] = candidates.indices.map { $0 }
        var keptByKey: [String: Int] = [:]

        for index in candidates.indices {
            guard let key = candidates[index].equalityKey else { continue }
            guard let existing = keptByKey[key] else {
                keptByKey[key] = index
                continue
            }
            if isBetter(candidates[index], than: candidates[existing]) {
                kept[existing] = nil
                keptByKey[key] = index
            } else {
                kept[index] = nil
            }
        }
        return kept.compactMap { $0 }
    }

    static func rank(_ candidates: [SearchEverywhereCandidate], limitPerProvider: Int) -> [Int] {
        let ordered = deduplicated(candidates).sorted { lhs, rhs in
            precedes(candidates[lhs], at: lhs, candidates[rhs], at: rhs)
        }
        var counts: [SearchEverywhereProvider: Int] = [:]
        return ordered.filter { index in
            let provider = candidates[index].provider
            let count = counts[provider, default: 0]
            guard count < limitPerProvider else { return false }
            counts[provider] = count + 1
            return true
        }
    }

    static func contiguousRuns<Element: Equatable & Sendable>(_ elements: [Element]) -> [SearchEverywhereRun<Element>] {
        var runs: [SearchEverywhereRun<Element>] = []
        var start = 0
        for index in elements.indices where index > 0 && elements[index] != elements[index - 1] {
            runs.append(SearchEverywhereRun(element: elements[start], range: start..<index))
            start = index
        }
        if start < elements.count {
            runs.append(SearchEverywhereRun(element: elements[start], range: start..<elements.count))
        }
        return runs
    }

    private static func isBetter(_ new: SearchEverywhereCandidate, than existing: SearchEverywhereCandidate) -> Bool {
        if new.weight != existing.weight {
            return new.weight > existing.weight
        }
        return new.provider.priority > existing.provider.priority
    }

    private static func precedes(
        _ lhs: SearchEverywhereCandidate,
        at lhsIndex: Int,
        _ rhs: SearchEverywhereCandidate,
        at rhsIndex: Int
    ) -> Bool {
        let sameProvider = lhs.provider == rhs.provider
        if shouldInsertAbove(
            newProviderPriority: lhs.provider.priority,
            newIsExactMatch: lhs.isExactMatch,
            newWeight: lhs.weight,
            itemProviderPriority: rhs.provider.priority,
            itemIsExactMatch: rhs.isExactMatch,
            itemWeight: rhs.weight,
            prioritizeExactMatch: sameProvider
        ) {
            return true
        }
        if shouldInsertAbove(
            newProviderPriority: rhs.provider.priority,
            newIsExactMatch: rhs.isExactMatch,
            newWeight: rhs.weight,
            itemProviderPriority: lhs.provider.priority,
            itemIsExactMatch: lhs.isExactMatch,
            itemWeight: lhs.weight,
            prioritizeExactMatch: sameProvider
        ) {
            return false
        }
        if !lhs.provider.keepsDiscoveryOrder {
            let titleOrder = lhs.title.localizedStandardCompare(rhs.title)
            if titleOrder != .orderedSame {
                return titleOrder == .orderedAscending
            }
        }
        return lhsIndex < rhsIndex
    }
}
