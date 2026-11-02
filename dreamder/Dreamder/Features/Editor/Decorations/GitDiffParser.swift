import Foundation

enum GitDiffParser {
    struct Hunk: Equatable {
        let oldStart: Int
        let oldCount: Int
        let newStart: Int
        let newCount: Int
    }

    static func hunks(inDiff output: String) -> [Hunk] {
        output
            .split(separator: "\n", omittingEmptySubsequences: false)
            .compactMap(hunk(fromHeader:))
    }

    static func hunk(fromHeader line: Substring) -> Hunk? {
        guard line.hasPrefix("@@ ") else { return nil }
        let body = line.dropFirst(3)
        guard let terminator = body.range(of: "@@") else { return nil }
        let parts = body[..<terminator.lowerBound].split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 2,
              let old = parseRange(parts[0], prefix: "-"),
              let new = parseRange(parts[1], prefix: "+") else {
            return nil
        }
        return Hunk(oldStart: old.start, oldCount: old.count, newStart: new.start, newCount: new.count)
    }

    private static func parseRange(_ token: Substring, prefix: Character) -> (start: Int, count: Int)? {
        guard token.first == prefix else { return nil }
        let numbers = token.dropFirst().split(separator: ",", omittingEmptySubsequences: false)
        guard (1...2).contains(numbers.count),
              let start = Int(numbers[0]),
              start >= 0 else {
            return nil
        }
        guard numbers.count == 2 else { return (start, 1) }
        guard let count = Int(numbers[1]), count >= 0 else { return nil }
        return (start, count)
    }
}
