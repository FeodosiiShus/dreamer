import Foundation

nonisolated enum PreserveCase {
    nonisolated private struct WordCase {
        let upperCase: Bool
        let lowerCase: Bool
        let capitalized: Bool
    }

    static func replaceWithCaseRespect(_ toReplace: String, foundString: String) -> String {
        let replacement = Array(toReplace)
        let found = Array(foundString)
        guard let firstFound = found.first, let firstReplacement = replacement.first else { return toReplace }

        var result = String(firstFound.isUppercase ? upper(firstReplacement) : lower(firstReplacement))
        if replacement.count == 1 { return result }

        let replacementTail = replacement.dropFirst()
        if found.count == 1 {
            result += String(replacementTail)
            return result
        }

        var isReplacementLowercase = true
        var isReplacementUppercase = true
        for character in replacementTail where character.isLetter {
            isReplacementLowercase = isReplacementLowercase && character.isLowercase
            isReplacementUppercase = isReplacementUppercase && character.isUppercase
            if !isReplacementLowercase && !isReplacementUppercase { break }
        }

        var isTailUpper = true
        var isTailLower = true
        var isTailChecked = false
        for character in found.dropFirst() where character.isLetter {
            isTailUpper = isTailUpper && character.isUppercase
            isTailLower = isTailLower && character.isLowercase
            isTailChecked = true
            if !isTailUpper && !isTailLower { break }
        }
        if !isTailChecked {
            isTailUpper = firstFound.isLetter && firstFound.isUppercase
            isTailLower = firstFound.isLetter && firstFound.isLowercase
        }

        if isTailUpper && (isReplacementLowercase || !isReplacementUppercase) {
            result += String(replacementTail.map(upper))
        } else if isTailLower && (isReplacementLowercase || isReplacementUppercase) {
            result += String(replacementTail.map(lower))
        } else {
            result += String(replacementTail)
        }
        return result
    }

    static func applyCase(found: String, replacement: String) -> String {
        if found.isEmpty || replacement.isEmpty { return replacement }

        let words = collectWords(found)
        guard !words.isEmpty else { return replacement }

        var result = ""
        var index = 0
        var wordStart: Int?
        let characters = Array(replacement)
        for (position, character) in characters.enumerated() {
            if isLetterOrDigit(character) {
                if wordStart == nil { wordStart = position }
            } else {
                if let start = wordStart {
                    buildWord(
                        String(characters[start..<position]),
                        foundCase: analyze(words[index]),
                        result: &result
                    )
                    wordStart = nil
                    if index < words.count - 1 { index += 1 }
                }
                result.append(character)
            }
        }
        if let start = wordStart {
            buildWord(
                String(characters[start...]),
                foundCase: analyze(words[index]),
                result: &result
            )
        }
        return result
    }

    private static func analyze(_ word: String) -> WordCase {
        var upperCase = true
        var lowerCase = true
        var capitalized = true
        for character in word where character.isLetter {
            let isUpper = character.isUppercase
            let isLower = character.isLowercase
            if upperCase && lowerCase {
                capitalized = isUpper
            }
            upperCase = upperCase && isUpper
            lowerCase = lowerCase && isLower
        }
        return WordCase(upperCase: upperCase, lowerCase: lowerCase, capitalized: capitalized)
    }

    private static func collectWords(_ string: String) -> [String] {
        var words: [String] = []
        var word = ""
        var previousIsWordCharacter = false
        for character in string {
            if isLetterOrDigit(character) {
                previousIsWordCharacter = true
                word.append(character)
            } else if previousIsWordCharacter {
                words.append(word)
                word = ""
                previousIsWordCharacter = false
            }
        }
        if !word.isEmpty {
            words.append(word)
        }
        return words
    }

    private static func buildWord(_ word: String, foundCase: WordCase, result: inout String) {
        if foundCase.upperCase && foundCase.lowerCase {
            result += word
            return
        }
        let replacementCase = analyze(word)
        if foundCase.upperCase {
            result += replacementCase.upperCase ? word : word.uppercased()
            return
        }
        var previousIsWordCharacter = false
        for character in word {
            if character.isLetter {
                if !previousIsWordCharacter {
                    result.append(foundCase.lowerCase || !foundCase.capitalized ? lower(character) : upper(character))
                    previousIsWordCharacter = true
                } else {
                    result.append(replacementCase.upperCase ? lower(character) : character)
                }
            } else {
                previousIsWordCharacter = isDigit(character)
                result.append(character)
            }
        }
    }

    private static func isDigit(_ character: Character) -> Bool {
        character.unicodeScalars.first?.properties.generalCategory == .decimalNumber
    }

    private static func isLetterOrDigit(_ character: Character) -> Bool {
        character.isLetter || isDigit(character)
    }

    private static func upper(_ character: Character) -> Character {
        singleCharacter(of: String(character).uppercased(), fallback: character)
    }

    private static func lower(_ character: Character) -> Character {
        singleCharacter(of: String(character).lowercased(), fallback: character)
    }

    private static func singleCharacter(of converted: String, fallback: Character) -> Character {
        guard converted.count == 1, let only = converted.first else { return fallback }
        return only
    }
}
