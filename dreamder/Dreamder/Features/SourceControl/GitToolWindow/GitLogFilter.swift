import Foundation

nonisolated enum GitLogFilterKey: String, CaseIterable, Hashable, Sendable {
    case branch
    case revision
    case range
    case user
    case hash
    case date
    case text
    case structure
    case parent
}

nonisolated enum GitLogTextSyntax {
    static let regexCharacters = Set("()[]{}.*?+^$\\|")

    static func isRegexp(_ text: String) -> Bool {
        text.contains { regexCharacters.contains($0) }
    }

    static func compile(_ pattern: String, matchCase: Bool) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: matchCase ? [] : [.caseInsensitive])
    }

    static func matchesWhole(_ pattern: String, in text: String) -> Bool {
        guard let expression = compile("\\A(?:" + pattern + ")\\z", matchCase: true) else { return false }
        return expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}

nonisolated struct GitLogTextFilter: Hashable, Sendable {
    let text: String
    let isRegex: Bool
    let matchesCase: Bool

    static func fromPattern(_ text: String, isRegexpAllowed: Bool = false, isMatchCase: Bool = false) -> GitLogTextFilter {
        if isRegexpAllowed, GitLogTextSyntax.isRegexp(text), GitLogTextSyntax.compile(text, matchCase: isMatchCase) != nil {
            return GitLogTextFilter(text: text, isRegex: true, matchesCase: isMatchCase)
        }
        return GitLogTextFilter(text: text, isRegex: false, matchesCase: isMatchCase)
    }

    func matcher() -> GitLogTextMatcher {
        GitLogTextMatcher(filter: self)
    }
}

nonisolated struct GitLogTextMatcher {
    private let filter: GitLogTextFilter
    private let expression: NSRegularExpression?

    init(filter: GitLogTextFilter) {
        self.filter = filter
        self.expression = filter.isRegex ? GitLogTextSyntax.compile(filter.text, matchCase: filter.matchesCase) : nil
    }

    func matches(_ message: String) -> Bool {
        if filter.isRegex {
            guard let expression else { return false }
            return expression.firstMatch(in: message, range: NSRange(message.startIndex..., in: message)) != nil
        }
        if filter.text.isEmpty { return true }
        let options: String.CompareOptions = filter.matchesCase ? [] : [.caseInsensitive]
        return message.range(of: filter.text, options: options) != nil
    }
}

nonisolated struct GitLogUser: Hashable, Sendable {
    let name: String
    let email: String

    init(name: String, email: String) {
        self.name = name
        self.email = email.lowercased()
    }

    var exactString: String {
        if name.isEmpty { return email }
        if email.isEmpty { return name }
        return "\(name) <\(email)>"
    }

    var shortPresentation: String {
        GitLogUserNames.userName(name: name, email: email)
    }
}

nonisolated enum GitLogUserNames {
    static func nameFromEmail(_ email: String) -> String? {
        guard let at = email.firstIndex(of: "@"), at != email.startIndex else { return nil }
        return String(email[..<at])
    }

    static func userName(name: String, email: String) -> String {
        if !name.isEmpty { return name }
        return nameFromEmail(email) ?? email
    }

    static func nameToLowerCase(_ name: String) -> String {
        guard name.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value <= 0x7E }) else { return name }
        return name.lowercased()
    }

    static func nameInStandardForm(_ name: String) -> String {
        if let (first, last) = firstAndLastName(name) {
            return first.lowercased() + " " + last.lowercased()
        }
        return nameToLowerCase(name)
    }

    static func firstAndLastName(_ name: String) -> (String, String)? {
        let characters = Array(name)
        guard characters.count >= 3 else { return nil }
        var separator = characters.count - 2
        while separator >= 1 {
            let left = characters[..<separator]
            let right = characters[(separator + 1)...]
            if isSeparator(characters[separator]), left.allSatisfy(isWordCharacter), right.allSatisfy(isWordCharacter) {
                return (String(left), String(right))
            }
            separator -= 1
        }
        return nil
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        guard character.isASCII else { return false }
        return character.isLetter || character.isNumber || character == "_"
    }

    private static func isSeparator(_ character: Character) -> Bool {
        guard character.isASCII else { return false }
        return character.isPunctuation || character.isSymbol || character.isWhitespace
    }

    static func escapeBackSlashes(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
    }

    static let extendedRegexCharacters = Set(".^$*+-?()[]{}|")

    static func extendedRegex(for name: String) -> String {
        var escaped = ""
        for character in escapeBackSlashes(name) {
            if extendedRegexCharacters.contains(character) {
                escaped.append("\\")
            }
            escaped.append(character)
        }
        return "^" + escaped + "$"
    }
}

nonisolated struct GitLogUserResolver: Sendable {
    let currentUser: GitLogUser?
    let allUsers: [GitLogUser]
    private let usersByNames: [String: [GitLogUser]]
    private let usersByEmails: [String: [GitLogUser]]

    init(currentUser: GitLogUser? = nil, allUsers: [GitLogUser] = []) {
        self.currentUser = currentUser
        var unique: [GitLogUser] = []
        var seen = Set<GitLogUser>()
        for user in allUsers where seen.insert(user).inserted {
            unique.append(user)
        }
        self.allUsers = unique

        var byNames: [String: [GitLogUser]] = [:]
        var byEmails: [String: [GitLogUser]] = [:]
        for user in unique {
            if !user.name.isEmpty {
                byNames[GitLogUserNames.nameInStandardForm(user.name), default: []].append(user)
            }
            if let fromEmail = GitLogUserNames.nameFromEmail(user.email) {
                byEmails[GitLogUserNames.nameInStandardForm(fromEmail), default: []].append(user)
            }
        }
        self.usersByNames = byNames
        self.usersByEmails = byEmails
    }

    static func users(of commits: [GitLogCommit]) -> [GitLogUser] {
        commits.map { GitLogUser(name: $0.authorName, email: $0.authorEmail) }
    }

    func resolveUserName(_ name: String) -> [GitLogUser] {
        let standard = GitLogUserNames.nameInStandardForm(name)
        return Self.union(usersByNames[standard] ?? [], usersByEmails[standard] ?? [])
    }

    func resolveCurrentUser() -> [GitLogUser] {
        guard let currentUser else { return [] }
        let byName = resolveUserName(currentUser.name)
        guard let emailNamePart = GitLogUserNames.nameFromEmail(currentUser.email) else { return byName }
        let emails = Set(byName.map { $0.email.lowercased() })
        let byEmail = resolveUserName(emailNamePart).filter { emails.contains($0.email.lowercased()) }
        return Self.union(byName, byEmail)
    }

    private static func union(_ first: [GitLogUser], _ second: [GitLogUser]) -> [GitLogUser] {
        var result = first
        for user in second where !result.contains(user) {
            result.append(user)
        }
        return result
    }
}

nonisolated struct GitLogUserFilter: Hashable, Sendable {
    static let me = "*"

    let userNames: [String]

    var displayText: String {
        userNames.map { $0 == Self.me ? "me" : $0 }.joined(separator: ", ")
    }

    func users(resolver: GitLogUserResolver) -> [GitLogUser] {
        var result: [GitLogUser] = []
        for name in userNames {
            let resolved = name == Self.me ? resolver.resolveCurrentUser() : resolver.resolveUserName(name)
            for user in resolved where !result.contains(user) {
                result.append(user)
            }
        }
        return result
    }

    func matches(_ commit: GitLogCommit, resolver: GitLogUserResolver) -> Bool {
        let author = GitLogUser(name: commit.authorName, email: commit.authorEmail)
        return userNames.contains { name in
            let resolved = name == Self.me ? resolver.resolveCurrentUser() : resolver.resolveUserName(name)
            if !resolved.isEmpty {
                return resolved.contains(author)
            }
            guard name != Self.me else { return false }
            let lowerUser = GitLogUserNames.nameToLowerCase(name)
            return GitLogUserNames.nameToLowerCase(author.name) == lowerUser
                || author.email.lowercased().hasPrefix("\(lowerUser)@")
        }
    }
}

nonisolated struct GitLogDateFilter: Hashable, Sendable {
    let after: Date?
    let before: Date?

    func matches(_ commit: GitLogCommit) -> Bool {
        var result = true
        if let after {
            result = result && commit.commitDate > after
        }
        if let before {
            result = result && commit.commitDate < before
        }
        return result
    }
}

nonisolated struct GitLogParentFilter: Hashable, Sendable {
    let minParents: Int
    let maxParents: Int

    init(minParents: Int? = nil, maxParents: Int? = nil) {
        self.minParents = minParents ?? 0
        self.maxParents = maxParents ?? Int.max
    }

    static let noMerges = GitLogParentFilter(maxParents: 1)
    static let onlyMerges = GitLogParentFilter(minParents: 2)

    var hasLowerBound: Bool { minParents > 0 }
    var hasUpperBound: Bool { maxParents != Int.max }
    var matchesAll: Bool { minParents <= 0 && maxParents == Int.max }
    var isNoMerges: Bool { maxParents == 1 && !hasLowerBound }

    func matches(_ commit: GitLogCommit) -> Bool {
        commit.parents.count >= minParents && commit.parents.count <= maxParents
    }
}

nonisolated struct GitLogHashFilter: Hashable, Sendable {
    let hashes: [String]

    static func fromText(_ text: String) -> GitLogHashFilter? {
        let separators = CharacterSet(charactersIn: ",;").union(.whitespacesAndNewlines)
        var hashes: [String] = []
        for word in text.components(separatedBy: separators) where !word.isEmpty {
            guard isHash(word) else { return nil }
            hashes.append(word)
        }
        return hashes.isEmpty ? nil : GitLogHashFilter(hashes: hashes)
    }

    static func isHash(_ word: String) -> Bool {
        (7...64).contains(word.count) && word.allSatisfy { $0.isASCII && $0.isHexDigit }
    }

    var displayText: String {
        hashes.map { String($0.prefix(8)) }.joined(separator: ", ")
    }

    func matchesPrefix(_ commit: GitLogCommit) -> Bool {
        let hash = commit.hash.lowercased()
        return hashes.contains { hash.hasPrefix($0.lowercased()) }
    }

    func toTextFilter() -> GitLogMultiPatternFilter {
        GitLogMultiPatternFilter(patterns: hashes)
    }
}

nonisolated struct GitLogMultiPatternFilter: Hashable, Sendable {
    let patterns: [String]

    func matches(_ message: String) -> Bool {
        patterns.contains { message.range(of: $0, options: .caseInsensitive) != nil }
    }
}

nonisolated struct GitLogBranchFilter: Hashable, Sendable {
    let branches: [String]
    let patterns: [String]
    let excludedBranches: [String]
    let excludedPatterns: [String]

    init(
        branches: [String] = [],
        patterns: [String] = [],
        excludedBranches: [String] = [],
        excludedPatterns: [String] = []
    ) {
        self.branches = branches
        self.patterns = patterns
        self.excludedBranches = excludedBranches
        self.excludedPatterns = excludedPatterns
    }

    static func fromBranch(_ name: String) -> GitLogBranchFilter {
        GitLogBranchFilter(branches: [name])
    }

    static func fromPatterns(
        _ patterns: [String],
        existingBranches: Set<String>,
        excludeNotMatched: Bool = false
    ) -> GitLogBranchFilter {
        var included: [String] = []
        var excluded: [String] = []
        var includedPatterns: [String] = []
        var excludedPatterns: [String] = []
        let shouldExcludeNotMatched = !existingBranches.isEmpty && excludeNotMatched

        for pattern in patterns {
            let isExcluded = pattern.hasPrefix("-")
            let string = isExcluded ? String(pattern.dropFirst()) : pattern
            let isRegexp = !existingBranches.contains(string) && GitLogTextSyntax.isRegexp(string)

            if isRegexp, GitLogTextSyntax.compile(string, matchCase: true) != nil {
                if isExcluded {
                    excludedPatterns.append(string)
                } else {
                    includedPatterns.append(string)
                }
                continue
            }
            if shouldExcludeNotMatched && !existingBranches.contains(string) {
                continue
            }
            if isExcluded {
                excluded.append(string)
            } else {
                included.append(string)
            }
        }
        return GitLogBranchFilter(
            branches: included,
            patterns: includedPatterns,
            excludedBranches: excluded,
            excludedPatterns: excludedPatterns
        )
    }

    var isEmpty: Bool {
        branches.isEmpty && patterns.isEmpty && excludedBranches.isEmpty && excludedPatterns.isEmpty
    }

    var displayText: String {
        (branches + patterns + excludedBranches.map { "-" + $0 } + excludedPatterns.map { "-" + $0 })
            .joined(separator: ", ")
    }

    func matches(_ name: String) -> Bool {
        isIncluded(name) && !isExcluded(name)
    }

    private func isIncluded(_ name: String) -> Bool {
        if patterns.isEmpty && branches.isEmpty { return true }
        return Self.isMatched(name, branches: branches, patterns: patterns)
    }

    private func isExcluded(_ name: String) -> Bool {
        Self.isMatched(name, branches: excludedBranches, patterns: excludedPatterns)
    }

    private static func isMatched(_ name: String, branches: [String], patterns: [String]) -> Bool {
        if branches.contains(name) { return true }
        return patterns.contains { GitLogTextSyntax.matchesWhole($0, in: name) }
    }
}

nonisolated struct GitLogRefRange: Hashable, Sendable {
    let exclusiveRef: String
    let inclusiveRef: String
}

nonisolated struct GitLogRangeFilter: Hashable, Sendable {
    let ranges: [GitLogRefRange]
}

nonisolated struct GitLogRevisionFilter: Hashable, Sendable {
    let heads: [String]
}

nonisolated struct GitLogStructureFilter: Hashable, Sendable {
    let paths: [String]
}

nonisolated struct GitLogOptions: Hashable, Sendable {
    var firstParent = false
}

nonisolated struct GitLogFilterCollection: Hashable, Sendable {
    var branch: GitLogBranchFilter?
    var range: GitLogRangeFilter?
    var revision: GitLogRevisionFilter?
    var user: GitLogUserFilter?
    var hash: GitLogHashFilter?
    var date: GitLogDateFilter?
    var text: GitLogTextFilter?
    var structure: GitLogStructureFilter?
    var parent: GitLogParentFilter?

    init(
        branch: GitLogBranchFilter? = nil,
        range: GitLogRangeFilter? = nil,
        revision: GitLogRevisionFilter? = nil,
        user: GitLogUserFilter? = nil,
        hash: GitLogHashFilter? = nil,
        date: GitLogDateFilter? = nil,
        text: GitLogTextFilter? = nil,
        structure: GitLogStructureFilter? = nil,
        parent: GitLogParentFilter? = nil
    ) {
        self.branch = branch
        self.range = range
        self.revision = revision
        self.user = user
        self.hash = hash
        self.date = date
        self.text = text
        self.structure = structure
        self.parent = parent
    }

    var keys: Set<GitLogFilterKey> {
        var result = Set<GitLogFilterKey>()
        if let branch, !branch.isEmpty { result.insert(.branch) }
        if range != nil { result.insert(.range) }
        if revision != nil { result.insert(.revision) }
        if user != nil { result.insert(.user) }
        if hash != nil { result.insert(.hash) }
        if date != nil { result.insert(.date) }
        if text != nil { result.insert(.text) }
        if let structure, !structure.paths.isEmpty { result.insert(.structure) }
        if let parent, !parent.matchesAll { result.insert(.parent) }
        return result
    }

    var isEmpty: Bool {
        keys.isEmpty
    }

    var repositoryFilters: GitLogFilterCollection {
        GitLogFilterCollection(branch: branch, range: range, revision: revision, structure: structure)
    }

    var hasDetailsFilters: Bool {
        !keys.isDisjoint(with: [.user, .date, .text, .parent, .hash])
    }

    func applyingInMemory(to commits: [GitLogCommit], resolver: GitLogUserResolver) -> [GitLogCommit] {
        if let hash, !hash.hashes.isEmpty {
            let textFilter = hash.toTextFilter()
            let union = commits.filter { hash.matchesPrefix($0) || textFilter.matches($0.message) }
            if !union.isEmpty {
                return union
            }
        }

        let matcher = text?.matcher()
        let activeParent = parent.flatMap { $0.matchesAll ? nil : $0 }
        return commits.filter { commit in
            if let activeParent, !activeParent.matches(commit) { return false }
            if let matcher, !matcher.matches(commit.message) { return false }
            if let user, !user.matches(commit, resolver: resolver) { return false }
            if let date, !date.matches(commit) { return false }
            return true
        }
    }
}

nonisolated enum GitLogDatePreset: String, CaseIterable, Identifiable, Sendable {
    case last24Hours
    case last7Days
    case last30Days
    case lastYear

    var id: String { rawValue }

    var title: String {
        switch self {
        case .last24Hours: "Last 24 hours"
        case .last7Days: "Last 7 days"
        case .last30Days: "Last 30 days"
        case .lastYear: "Last year"
        }
    }

    var interval: TimeInterval {
        switch self {
        case .last24Hours: 24 * 3600
        case .last7Days: 7 * 24 * 3600
        case .last30Days: 30 * 24 * 3600
        case .lastYear: 365 * 24 * 3600
        }
    }

    func filter(now: Date = Date()) -> GitLogDateFilter {
        GitLogDateFilter(after: now.addingTimeInterval(-interval), before: nil)
    }
}

nonisolated extension GitLogFilterCollection {
    func settingText(_ input: String, isRegexpAllowed: Bool, isMatchCase: Bool) -> GitLogFilterCollection {
        var result = self
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            result.text = nil
            result.hash = nil
        } else {
            result.text = GitLogTextFilter.fromPattern(trimmed, isRegexpAllowed: isRegexpAllowed, isMatchCase: isMatchCase)
            result.hash = GitLogHashFilter.fromText(trimmed)
        }
        return result
    }

    func settingUserNames(_ names: [String]) -> GitLogFilterCollection {
        var result = self
        result.user = names.isEmpty ? nil : GitLogUserFilter(userNames: names)
        return result
    }

    func settingDate(after: Date?, before: Date?) -> GitLogFilterCollection {
        var result = self
        result.date = after == nil && before == nil ? nil : GitLogDateFilter(after: after, before: before)
        return result
    }

    func settingPaths(from input: String) -> GitLogFilterCollection {
        var result = self
        let paths = input
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        result.structure = paths.isEmpty ? nil : GitLogStructureFilter(paths: paths)
        return result
    }

    func settingParent(_ filter: GitLogParentFilter?) -> GitLogFilterCollection {
        var result = self
        result.parent = filter
        return result
    }
}
