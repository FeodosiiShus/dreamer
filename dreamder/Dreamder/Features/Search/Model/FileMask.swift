import Foundation

nonisolated struct FileMask: Sendable {
    private let matcher: NSRegularExpression?
    private let exclusion: NSRegularExpression?

    init(filter: String?) throws {
        guard let filter, !filter.isEmpty else {
            matcher = nil
            exclusion = nil
            return
        }

        var included: [String] = []
        var excluded: [String] = []
        for part in filter.split(separator: ",", omittingEmptySubsequences: true) {
            let mask = part.trimmingCharacters(in: .whitespaces)
            if mask.hasPrefix("!") {
                excluded.append("(\(Self.convertToRegex(String(mask.dropFirst()))))")
            } else {
                included.append("(\(Self.convertToRegex(mask)))")
            }
        }
        if included.isEmpty {
            included.append(Self.convertToRegex("*"))
        }

        matcher = try Self.compile(included.joined(separator: "|"))
        exclusion = try excluded.isEmpty ? nil : Self.compile(excluded.joined(separator: "|"))
    }

    func accepts(_ fileName: String) -> Bool {
        guard let matcher else { return true }
        guard Self.matchesEntirely(matcher, fileName) else { return false }
        guard let exclusion else { return true }
        return !Self.matchesEntirely(exclusion, fileName)
    }

    static func convertToRegex(_ mask: String) -> String {
        mask.split(separator: "\\", omittingEmptySubsequences: true)
            .map { segment in
                segment.reduce(into: "") { result, character in
                    switch character {
                    case "*": result += ".*"
                    case "?": result += "."
                    case ".": result += "\\."
                    case "+", "(", ")", "[", "]", "/", "^", "$", "{", "}", "|":
                        result += "\\\(character)"
                    default: result.append(character)
                    }
                }
            }
            .joined(separator: "\\\\")
    }

    private static func compile(_ pattern: String) throws -> NSRegularExpression {
        try NSRegularExpression(pattern: "\\A(?:\(pattern))\\z", options: [.caseInsensitive])
    }

    private static func matchesEntirely(_ regex: NSRegularExpression, _ text: String) -> Bool {
        regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)) != nil
    }
}
