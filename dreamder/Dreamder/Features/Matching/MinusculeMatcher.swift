import Foundation

nonisolated enum MatchingCaseMode: Sendable {
    case ignoreCase
    case firstLetter
    case matchCase
}

nonisolated struct MinusculeMatcher: Sendable {
    static let startMatchWeight = 10000

    let pattern: String
    private let main: MinusculeMatcherCore
    private let fallback: MinusculeMatcherCore?
    private let preferStartMatch: Bool

    init(
        pattern: String,
        mode: MatchingCaseMode = .ignoreCase,
        hardSeparators: String = "",
        preferStartMatch: Bool = false,
        fixKeyboardLayout: Bool = true
    ) {
        let core = MinusculeMatcherCore(pattern: pattern, mode: mode, hardSeparators: hardSeparators)
        self.pattern = String(decoding: core.pattern, as: UTF16.self)
        main = core
        if fixKeyboardLayout, let fixed = RussianToEnglishKeyboardLayout.fixLayout(pattern), fixed != pattern {
            fallback = MinusculeMatcherCore(pattern: fixed, mode: mode, hardSeparators: hardSeparators)
        } else {
            fallback = nil
        }
        self.preferStartMatch = preferStartMatch
    }

    func match(_ name: String) -> [Range<Int>]? {
        resolve(Array(name.utf16)).ranges
    }

    func matches(_ name: String) -> Bool {
        let units = Array(name.utf16)
        if preferStartMatch {
            return resolve(units).ranges != nil
        }
        if main.match(units) != nil {
            return true
        }
        guard let fallback else { return false }
        return fallback.match(units) != nil
    }

    func matchingDegree(_ name: String) -> Int {
        let units = Array(name.utf16)
        let resolved = resolve(units)
        return degree(units, valueStartCaseMatch: false, fragments: resolved.ranges, core: resolved.core)
    }

    func matchingDegree(_ name: String, valueStartCaseMatch: Bool, fragments: [Range<Int>]?) -> Int {
        let units = Array(name.utf16)
        let core = resolve(units).core
        return degree(units, valueStartCaseMatch: valueStartCaseMatch, fragments: fragments, core: core)
    }

    func isStartMatch(_ name: String) -> Bool {
        guard let fragments = match(name) else { return false }
        return fragments.first.map { $0.lowerBound == 0 } ?? true
    }

    func matchWithDegree(_ name: String) -> (fragments: [Range<Int>], degree: Int)? {
        let units = Array(name.utf16)
        let resolved = resolve(units)
        guard let fragments = resolved.ranges else { return nil }
        let value = degree(units, valueStartCaseMatch: false, fragments: fragments, core: resolved.core)
        return (fragments, value)
    }

    private func resolve(_ units: [UInt16]) -> (ranges: [Range<Int>]?, core: MinusculeMatcherCore) {
        let mainRanges = main.match(units)
        if let mainRanges, !mainRanges.isEmpty {
            return (mainRanges, main)
        }
        guard let fallback else {
            return (mainRanges, main)
        }
        return (fallback.match(units), fallback)
    }

    private func degree(
        _ units: [UInt16],
        valueStartCaseMatch: Bool,
        fragments: [Range<Int>]?,
        core: MinusculeMatcherCore
    ) -> Int {
        let base = core.matchingDegree(units, valueStartCaseMatch: valueStartCaseMatch, fragments: fragments)
        guard preferStartMatch, let first = fragments?.first, first.lowerBound == 0 else {
            return base
        }
        return base + Self.startMatchWeight
    }
}
