import Foundation

nonisolated enum MatchingCharacter {
    static func isUpperCase(_ c: UInt32) -> Bool {
        if c < 0x80 {
            return c >= 0x41 && c <= 0x5A
        }
        guard let scalar = Unicode.Scalar(c) else { return false }
        return scalar.properties.isUppercase
    }

    static func isLowerCase(_ c: UInt32) -> Bool {
        if c < 0x80 {
            return c >= 0x61 && c <= 0x7A
        }
        guard let scalar = Unicode.Scalar(c) else { return false }
        return scalar.properties.isLowercase
    }

    static func isDigit(_ c: UInt32) -> Bool {
        if c < 0x80 {
            return c >= 0x30 && c <= 0x39
        }
        guard let scalar = Unicode.Scalar(c) else { return false }
        return scalar.properties.generalCategory == .decimalNumber
    }

    static func isLetter(_ c: UInt32) -> Bool {
        if c < 0x80 {
            return (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A)
        }
        guard let scalar = Unicode.Scalar(c) else { return false }
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter:
            return true
        default:
            return false
        }
    }

    static func isLetterOrDigit(_ c: UInt32) -> Bool {
        isLetter(c) || isDigit(c)
    }

    static func isWhitespace(_ c: UInt32) -> Bool {
        if c < 0x80 {
            return c == 0x20 || (c >= 0x09 && c <= 0x0D) || (c >= 0x1C && c <= 0x1F)
        }
        guard let scalar = Unicode.Scalar(c) else { return false }
        switch scalar.properties.generalCategory {
        case .spaceSeparator, .lineSeparator, .paragraphSeparator:
            return true
        default:
            return false
        }
    }

    static func isIdeographic(_ c: UInt32) -> Bool {
        guard let scalar = Unicode.Scalar(c) else { return false }
        return scalar.properties.isIdeographic
    }

    static func isMark(_ c: UInt32) -> Bool {
        guard let scalar = Unicode.Scalar(c) else { return false }
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark:
            return true
        default:
            return false
        }
    }

    static func uppercased(_ c: UInt32) -> UInt32 {
        if c < 0x80 {
            return c >= 0x61 && c <= 0x7A ? c - 0x20 : c
        }
        guard let scalar = Unicode.Scalar(c) else { return c }
        let mapping = scalar.properties.uppercaseMapping.unicodeScalars
        guard mapping.count == 1, let mapped = mapping.first, mapped.value <= 0xFFFF else { return c }
        return mapped.value
    }

    static func lowercased(_ c: UInt32) -> UInt32 {
        if c < 0x80 {
            return c >= 0x41 && c <= 0x5A ? c + 0x20 : c
        }
        guard let scalar = Unicode.Scalar(c) else { return c }
        let mapping = scalar.properties.lowercaseMapping.unicodeScalars
        guard mapping.count == 1, let mapped = mapping.first, mapped.value <= 0xFFFF else { return c }
        return mapped.value
    }

    static func equals(_ a: UInt32, _ b: UInt32, ignoreCase: Bool) -> Bool {
        if a == b { return true }
        if !ignoreCase { return false }
        let upperA = uppercased(a)
        let upperB = uppercased(b)
        return upperA == upperB || lowercased(upperA) == lowercased(upperB)
    }

    static func isUpperCase(_ unit: UInt16) -> Bool { isUpperCase(UInt32(unit)) }
    static func isLowerCase(_ unit: UInt16) -> Bool { isLowerCase(UInt32(unit)) }
    static func isDigit(_ unit: UInt16) -> Bool { isDigit(UInt32(unit)) }
    static func isLetter(_ unit: UInt16) -> Bool { isLetter(UInt32(unit)) }
    static func isLetterOrDigit(_ unit: UInt16) -> Bool { isLetterOrDigit(UInt32(unit)) }
    static func isWhitespace(_ unit: UInt16) -> Bool { isWhitespace(UInt32(unit)) }

    static func uppercased(_ unit: UInt16) -> UInt16 {
        UInt16(truncatingIfNeeded: uppercased(UInt32(unit)))
    }

    static func lowercased(_ unit: UInt16) -> UInt16 {
        UInt16(truncatingIfNeeded: lowercased(UInt32(unit)))
    }

    static func equals(_ a: UInt16, _ b: UInt16, ignoreCase: Bool) -> Bool {
        equals(UInt32(a), UInt32(b), ignoreCase: ignoreCase)
    }

    static func isHighSurrogate(_ unit: UInt16) -> Bool {
        unit >= 0xD800 && unit <= 0xDBFF
    }

    static func isLowSurrogate(_ unit: UInt16) -> Bool {
        unit >= 0xDC00 && unit <= 0xDFFF
    }
}
