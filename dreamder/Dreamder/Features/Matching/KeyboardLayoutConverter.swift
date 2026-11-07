import Foundation

nonisolated enum RussianToEnglishKeyboardLayout {
    private static let table: [UInt16: UInt16] = {
        let pairs: [(Character, Character)] = [
            ("й", "q"), ("ц", "w"), ("у", "e"), ("к", "r"), ("е", "t"), ("н", "y"), ("г", "u"), ("ш", "i"),
            ("щ", "o"), ("з", "p"), ("х", "["), ("ъ", "]"), ("ф", "a"), ("ы", "s"), ("в", "d"), ("а", "f"),
            ("п", "g"), ("р", "h"), ("о", "j"), ("л", "k"), ("д", "l"), ("ж", ";"), ("э", "'"), ("я", "z"),
            ("ч", "x"), ("с", "c"), ("м", "v"), ("и", "b"), ("т", "n"), ("ь", "m"), ("б", ","), ("ю", "."),
            (".", "/")
        ]
        var result: [UInt16: UInt16] = [:]
        for (from, to) in pairs {
            if let source = from.utf16.first, let target = to.utf16.first {
                result[source] = target
            }
        }
        return result
    }()

    static func convert(_ unit: UInt16) -> UInt16? {
        table[unit]
    }

    static func asciiForCharacter(_ unit: UInt16) -> UInt16? {
        let lowercased = MatchingCharacter.lowercased(unit)
        guard let converted = convert(lowercased) else { return nil }
        return lowercased == unit ? converted : MatchingCharacter.uppercased(converted)
    }

    static func fixLayout(_ pattern: String) -> String? {
        let units = Array(pattern.utf16)
        var hasLetters = false
        var onlyWrongLetters = true
        for unit in units where MatchingCharacter.isLetter(unit) {
            hasLetters = true
            if unit <= 0x7F {
                onlyWrongLetters = false
                break
            }
        }
        guard hasLetters, onlyWrongLetters else { return nil }
        var fixed = units
        for index in fixed.indices {
            if let converted = asciiForCharacter(fixed[index]) {
                fixed[index] = converted
            }
        }
        return String(decoding: fixed, as: UTF16.self)
    }
}
