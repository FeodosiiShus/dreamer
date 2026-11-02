import Foundation

struct SearchEverywhereQuery: Equatable {
    let text: String
    let line: Int?
    let column: Int?

    init(text: String, line: Int? = nil, column: Int? = nil) {
        self.text = text
        self.line = line
        self.column = column
    }

    static func parse(_ raw: String) -> SearchEverywhereQuery {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return SearchEverywhereQuery(text: "")
        }

        var pieces = trimmed.components(separatedBy: ":")
        guard pieces.count >= 2 else {
            return SearchEverywhereQuery(text: trimmed)
        }

        func isNumber(_ value: String) -> Bool {
            !value.isEmpty && value.allSatisfy { $0.isNumber }
        }

        var line: Int?
        var column: Int?

        if let last = pieces.last, isNumber(last), let value = Int(last), value > 0 {
            if pieces.count >= 3 {
                let previous = pieces[pieces.count - 2]
                if isNumber(previous), let second = Int(previous), second > 0 {
                    column = value
                    line = second
                    pieces.removeLast(2)
                } else {
                    line = value
                    pieces.removeLast()
                }
            } else {
                line = value
                pieces.removeLast()
            }
        }

        let text = pieces.joined(separator: ":")
        guard !text.isEmpty else {
            return SearchEverywhereQuery(text: trimmed)
        }
        return SearchEverywhereQuery(text: text, line: line, column: column)
    }
}

struct SearchEverywhereMatch: Equatable {
    let score: Int
    let ranges: [NSRange]
}

enum SearchEverywhereMatcher {
    static func match(query: String, in candidate: String) -> SearchEverywhereMatch? {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            return SearchEverywhereMatch(score: 0, ranges: [])
        }
        guard !candidate.isEmpty else {
            return nil
        }

        let candidateString = candidate as NSString
        let lengthPenalty = min(candidate.utf16.count, 200) / 40
        let wholeRange = NSRange(location: 0, length: candidateString.length)

        if candidateString.compare(query, options: .caseInsensitive) == .orderedSame {
            return SearchEverywhereMatch(score: 1000, ranges: [wholeRange])
        }

        let prefix = candidateString.range(
            of: query,
            options: [.caseInsensitive, .anchored],
            range: wholeRange
        )
        if prefix.location != NSNotFound {
            return SearchEverywhereMatch(score: 900 - lengthPenalty, ranges: [prefix])
        }

        if let ranges = wordStartRanges(query: query, candidate: candidate) {
            let score = 800 + min(ranges.count, 10) * 5 - lengthPenalty
            return SearchEverywhereMatch(score: score, ranges: ranges)
        }

        let substring = candidateString.range(of: query, options: .caseInsensitive, range: wholeRange)
        if substring.location != NSNotFound {
            let locationPenalty = min(substring.location, 100) / 25
            return SearchEverywhereMatch(score: 600 - locationPenalty, ranges: [substring])
        }

        if let ranges = subsequenceRanges(query: query, candidate: candidate) {
            let gaps = ranges.reduce(0) { partial, range in
                partial + max(0, range.location) / 8
            }
            let score = 300 - min(gaps, 60) - lengthPenalty
            return SearchEverywhereMatch(score: max(score, 120), ranges: ranges)
        }

        return nil
    }

    private static func wordStartRanges(query: String, candidate: String) -> [NSRange]? {
        let characters = Array(candidate)
        let offsets = utf16Offsets(for: characters)
        let queryCharacters = Array(query.lowercased())

        var ranges: [NSRange] = []
        var searchFrom = 0

        for queryCharacter in queryCharacters {
            var found: Int?
            var index = searchFrom
            while index < characters.count {
                if isWordStart(characters, at: index),
                   characters[index].lowercased() == String(queryCharacter) {
                    found = index
                    break
                }
                index += 1
            }
            guard let position = found else {
                return nil
            }
            let length = String(characters[position]).utf16.count
            ranges.append(NSRange(location: offsets[position], length: length))
            searchFrom = position + 1
        }

        return ranges
    }

    private static func subsequenceRanges(query: String, candidate: String) -> [NSRange]? {
        let characters = Array(candidate)
        let offsets = utf16Offsets(for: characters)
        let queryCharacters = Array(query.lowercased())

        var ranges: [NSRange] = []
        var searchFrom = 0

        for queryCharacter in queryCharacters {
            var found: Int?
            var index = searchFrom
            while index < characters.count {
                if characters[index].lowercased() == String(queryCharacter) {
                    found = index
                    break
                }
                index += 1
            }
            guard let position = found else {
                return nil
            }
            let length = String(characters[position]).utf16.count
            ranges.append(NSRange(location: offsets[position], length: length))
            searchFrom = position + 1
        }

        return ranges
    }

    private static func utf16Offsets(for characters: [Character]) -> [Int] {
        var offsets: [Int] = []
        offsets.reserveCapacity(characters.count)
        var offset = 0
        for character in characters {
            offsets.append(offset)
            offset += String(character).utf16.count
        }
        return offsets
    }

    private static func isWordStart(_ characters: [Character], at index: Int) -> Bool {
        guard index > 0 else { return true }
        let previous = characters[index - 1]
        let current = characters[index]

        if !previous.isLetter && !previous.isNumber {
            return true
        }
        if previous.isLowercase && current.isUppercase {
            return true
        }
        if previous.isNumber && current.isLetter {
            return true
        }
        return false
    }
}
