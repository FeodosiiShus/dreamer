import Foundation
import LanguageServerProtocol

nonisolated enum LSPFileGlob {
    static func matches(_ glob: String, path: String, ignoreCase: Bool) -> Bool {
        guard let body = regularExpression(for: glob) else { return false }
        let options: NSRegularExpression.Options = ignoreCase ? [.caseInsensitive] : []
        guard let expression = try? NSRegularExpression(pattern: "\\A" + body + "\\z", options: options) else {
            return false
        }
        return expression.firstMatch(in: path, range: NSRange(location: 0, length: (path as NSString).length)) != nil
    }

    static func regularExpression(for glob: String) -> String? {
        let characters = Array(glob)
        var output = ""
        var index = 0
        var braceDepth = 0
        while index < characters.count {
            let character = characters[index]
            switch character {
            case "*":
                var end = index + 1
                while end < characters.count, characters[end] == "*" { end += 1 }
                if end - index == 1 {
                    output += "[^/]*"
                    index = end
                } else if end < characters.count, characters[end] == "/" {
                    output += "(?:[^/]*/)*"
                    index = end + 1
                } else {
                    output += ".*"
                    index = end
                }
            case "?":
                output += "[^/]"
                index += 1
            case "{":
                braceDepth += 1
                output += "(?:"
                index += 1
            case "}":
                if braceDepth > 0 {
                    braceDepth -= 1
                    output += ")"
                } else {
                    output += "\\}"
                }
                index += 1
            case ",":
                output += braceDepth > 0 ? "|" : ","
                index += 1
            case "[":
                if let (bracket, next) = characterClass(in: characters, from: index) {
                    output += bracket
                    index = next
                } else {
                    output += "\\["
                    index += 1
                }
            default:
                output += NSRegularExpression.escapedPattern(for: String(character))
                index += 1
            }
        }
        return braceDepth == 0 ? output : nil
    }

    private static func characterClass(in characters: [Character], from start: Int) -> (String, Int)? {
        var contentStart = start + 1
        var negated = false
        if contentStart < characters.count, characters[contentStart] == "!" {
            negated = true
            contentStart += 1
        }
        var end = contentStart
        while end < characters.count, characters[end] != "]" { end += 1 }
        guard end < characters.count, end > contentStart else { return nil }
        var body = ""
        for character in characters[contentStart..<end] {
            if "\\[^&".contains(character) {
                body += "\\"
            }
            body.append(character)
        }
        let bracket = negated ? "[^" + body + "/]" : "[" + body + "]"
        return (bracket, end + 1)
    }
}

nonisolated enum LSPFileOperationFilterMatcher {
    static func matches(
        _ options: FileOperationRegistrationOptions,
        uri: String,
        isDirectory: Bool,
        rootPath: String?
    ) -> Bool {
        options.filters.contains { matches($0, uri: uri, isDirectory: isDirectory, rootPath: rootPath) }
    }

    static func matches(
        _ filter: FileOperationFilter,
        uri: String,
        isDirectory: Bool,
        rootPath: String?
    ) -> Bool {
        let parsed = location(of: uri)
        if let scheme = filter.scheme, scheme.lowercased() != parsed.scheme?.lowercased() {
            return false
        }
        if let kind = filter.pattern.matches, (kind == .folder) != isDirectory {
            return false
        }
        let ignoreCase = filter.pattern.options?.ignoreCase ?? false
        return candidatePaths(for: parsed.path, rootPath: rootPath).contains {
            LSPFileGlob.matches(filter.pattern.glob, path: $0, ignoreCase: ignoreCase)
        }
    }

    static func location(of uri: String) -> (scheme: String?, path: String) {
        guard let separator = uri.range(of: "://") else { return (nil, uri) }
        let scheme = String(uri[..<separator.lowerBound])
        let rest = String(uri[separator.upperBound...])
        let path = rest.firstIndex(of: "/").map { String(rest[$0...]) } ?? ""
        return (scheme, path.removingPercentEncoding ?? path)
    }

    private static func candidatePaths(for path: String, rootPath: String?) -> [String] {
        guard let rootPath, !rootPath.isEmpty else { return [path] }
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard path.hasPrefix(prefix) else { return [path] }
        return [path, String(path.dropFirst(prefix.count))]
    }
}
