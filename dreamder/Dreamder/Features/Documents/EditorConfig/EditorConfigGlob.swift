import Foundation

nonisolated enum EditorConfigGlob {
    static func matches(pattern: String, relativePath: String) -> Bool {
        let anchored = pattern.contains("/")
        let effective = pattern.hasPrefix("/") ? String(pattern.dropFirst()) : pattern
        var numericRanges: [ClosedRange<Int>] = []
        let body = translate(Array(effective), numericRanges: &numericRanges)
        let prefix = anchored ? "" : "(?:.*/)?"
        let source = "\\A(?:" + prefix + body + ")\\z"
        guard let regex = try? NSRegularExpression(pattern: source, options: [.dotMatchesLineSeparators]),
              let match = regex.firstMatch(
                in: relativePath,
                range: NSRange(relativePath.startIndex..., in: relativePath)
              )
        else {
            return false
        }
        for (index, allowed) in numericRanges.enumerated() {
            let groupRange = match.range(at: index + 1)
            if groupRange.location == NSNotFound {
                continue
            }
            guard let range = Range(groupRange, in: relativePath),
                  let number = Int(relativePath[range]),
                  String(number) == String(relativePath[range]),
                  allowed.contains(number)
            else {
                return false
            }
        }
        return true
    }

    private static func translate(_ pattern: [Character], numericRanges: inout [ClosedRange<Int>]) -> String {
        var result = ""
        var index = 0
        var braceLevel = 0
        let balanced = unescapedCount(of: "{", in: pattern) == unescapedCount(of: "}", in: pattern)
        while index < pattern.count {
            let character = pattern[index]
            index += 1
            switch character {
            case "\\":
                if index < pattern.count {
                    result += literal(pattern[index])
                    index += 1
                } else {
                    result += "\\\\"
                }
            case "*":
                if index < pattern.count, pattern[index] == "*" {
                    index += 1
                    result += ".*"
                } else {
                    result += "[^/]*"
                }
            case "?":
                result += "[^/]"
            case "[":
                if let (next, characterClass) = bracketClass(in: pattern, from: index) {
                    result += characterClass
                    index = next
                } else {
                    result += "\\["
                }
            case "{":
                var position = index
                var escaped = false
                var hasComma = false
                while position < pattern.count {
                    let scanned = pattern[position]
                    if escaped {
                        escaped = false
                    } else if scanned == "\\" {
                        escaped = true
                    } else if scanned == "}" {
                        break
                    } else if scanned == "," {
                        hasComma = true
                        break
                    }
                    position += 1
                }
                if !hasComma, position < pattern.count {
                    let inner = Array(pattern[index..<position])
                    if let range = numericRange(String(inner)) {
                        numericRanges.append(range)
                        result += "([+-]?[0-9]+)"
                    } else {
                        result += "\\{" + translate(inner, numericRanges: &numericRanges) + "\\}"
                    }
                    index = position + 1
                } else if balanced {
                    result += "(?:"
                    braceLevel += 1
                } else {
                    result += "\\{"
                }
            case ",":
                result += braceLevel > 0 ? "|" : "\\,"
            case "}":
                if braceLevel > 0 {
                    result += ")"
                    braceLevel -= 1
                } else {
                    result += "\\}"
                }
            case "/":
                if pattern[index...].starts(with: ["*", "*", "/"]) {
                    result += "(?:/|/.*/)"
                    index += 3
                } else {
                    result += "/"
                }
            default:
                result += literal(character)
            }
        }
        return result
    }

    private static func bracketClass(in pattern: [Character], from start: Int) -> (Int, String)? {
        var index = start
        var negated = false
        if index < pattern.count, pattern[index] == "!" {
            negated = true
            index += 1
        }
        var body = ""
        while index < pattern.count {
            let character = pattern[index]
            if character == "]" {
                return (index + 1, "[" + (negated ? "^" : "") + body + "]")
            }
            if character == "/" {
                return nil
            }
            if character == "\\", index + 1 < pattern.count {
                body += literal(pattern[index + 1])
                index += 2
                continue
            }
            body += character == "-" ? "-" : literal(character)
            index += 1
        }
        return nil
    }

    private static func numericRange(_ text: String) -> ClosedRange<Int>? {
        let parts = text.components(separatedBy: "..")
        guard parts.count == 2, let lower = Int(parts[0]), let upper = Int(parts[1]), lower < upper else {
            return nil
        }
        return lower...upper
    }

    private static func unescapedCount(of target: Character, in pattern: [Character]) -> Int {
        var count = 0
        var escaped = false
        for character in pattern {
            if escaped {
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == target {
                count += 1
            }
        }
        return count
    }

    private static func literal(_ character: Character) -> String {
        let text = String(character)
        guard character.isASCII, character.isPunctuation || character.isSymbol else {
            return text
        }
        return "\\" + text
    }
}
