import Foundation

nonisolated enum NaturalComparator {
    private static let space: UInt16 = 0x20
    private static let zero: UInt16 = 0x30
    private static let nine: UInt16 = 0x39
    private static let hyphen: UInt16 = 0x2D
    private static let underscore: UInt16 = 0x5F

    static func compare(_ s1: [UInt16], _ s2: [UInt16], ignoreCase: Bool, likeFileNames: Bool) -> Int {
        let length1 = s1.count
        let length2 = s2.count
        var i = 0
        var j = 0
        while i < length1 && j < length2 {
            let ch1 = s1[i]
            let ch2 = s2[j]
            if (isDecimalDigit(ch1) || ch1 == space) && (isDecimalDigit(ch2) || ch2 == space) {
                let start1 = skip(s1, from: skip(s1, from: i, end: length1, char: space), end: length1, char: zero)
                let start2 = skip(s2, from: skip(s2, from: j, end: length2, char: space), end: length2, char: zero)

                let end1 = skipDigits(s1, from: start1, end: length1)
                let end2 = skipDigits(s2, from: start2, end: length2)

                let lengthDiff = (end1 - start1) - (end2 - start2)
                if lengthDiff != 0 { return lengthDiff }

                let numberDiff = compareRange(s1, s2, offset1: start1, offset2: start2, end1: end1)
                if numberDiff != 0 { return numberDiff }

                let fullLengthDiff = (end1 - i) - (end2 - j)
                if fullLengthDiff != 0 { return fullLengthDiff }

                let leadingDiff = compareRange(s1, s2, offset1: i, offset2: j, end1: start1)
                if leadingDiff != 0 { return leadingDiff }

                i = end1 - 1
                j = end2 - 1
            } else if likeFileNames {
                if ch1 != ch2 {
                    let diff: Int
                    if ch1 == hyphen && ch2 != underscore {
                        diff = compareChars(underscore, ch2, ignoreCase: ignoreCase)
                    } else if ch2 == hyphen && ch1 != underscore {
                        diff = compareChars(ch1, underscore, ignoreCase: ignoreCase)
                    } else {
                        diff = compareChars(ch1, ch2, ignoreCase: ignoreCase)
                    }
                    if diff != 0 { return diff }
                }
            } else {
                let diff = compareChars(ch1, ch2, ignoreCase: ignoreCase)
                if diff != 0 { return diff }
            }
            i += 1
            j += 1
        }
        if i < length1 { return 1 }
        if j < length2 { return -1 }
        if length1 != length2 { return length1 - length2 }
        return ignoreCase ? compare(s1, s2, ignoreCase: false, likeFileNames: likeFileNames) : 0
    }

    private static func compareRange(
        _ s1: [UInt16],
        _ s2: [UInt16],
        offset1: Int,
        offset2: Int,
        end1: Int
    ) -> Int {
        var i = offset1
        var j = offset2
        while i < end1 {
            guard i < s1.count, j < s2.count else { return 0 }
            let diff = Int(s1[i]) - Int(s2[j])
            if diff != 0 { return diff }
            i += 1
            j += 1
        }
        return 0
    }

    private static func compareChars(_ ch1: UInt16, _ ch2: UInt16, ignoreCase: Bool) -> Int {
        if ch1 == space && ch2 > space && ch2 < zero { return 1 }
        if ch2 == space && ch1 > space && ch1 < zero { return -1 }
        return compareUnits(ch1, ch2, ignoreCase: ignoreCase)
    }

    private static func compareUnits(_ c1: UInt16, _ c2: UInt16, ignoreCase: Bool) -> Int {
        var diff = Int(c1) - Int(c2)
        if diff == 0 || !ignoreCase { return diff }
        let u1 = toUpperCase(c1)
        let u2 = toUpperCase(c2)
        diff = Int(u1) - Int(u2)
        if diff != 0 {
            diff = Int(toLowerCase(u1)) - Int(toLowerCase(u2))
        }
        return diff
    }

    private static func isDecimalDigit(_ unit: UInt16) -> Bool {
        unit >= zero && unit <= nine
    }

    private static func skipDigits(_ units: [UInt16], from start: Int, end: Int) -> Int {
        var index = start
        while index < end && isDecimalDigit(units[index]) { index += 1 }
        return index
    }

    private static func skip(_ units: [UInt16], from start: Int, end: Int, char: UInt16) -> Int {
        var index = start
        while index < end && units[index] == char { index += 1 }
        return index
    }

    private static func toUpperCase(_ unit: UInt16) -> UInt16 {
        if unit < 0x61 { return unit }
        if unit <= 0x7A { return unit - 0x20 }
        return simpleMapping(unit) { $0.properties.uppercaseMapping }
    }

    private static func toLowerCase(_ unit: UInt16) -> UInt16 {
        if unit < 0x41 { return unit }
        if unit <= 0x5A { return unit + 0x20 }
        if unit < 0x80 { return unit }
        return simpleMapping(unit) { $0.properties.lowercaseMapping }
    }

    private static func simpleMapping(_ unit: UInt16, _ mapping: (Unicode.Scalar) -> String) -> UInt16 {
        guard let scalar = Unicode.Scalar(unit) else { return unit }
        let mapped = mapping(scalar).unicodeScalars
        guard mapped.count == 1, let first = mapped.first, first.value <= 0xFFFF else { return unit }
        return UInt16(truncatingIfNeeded: first.value)
    }
}

nonisolated extension String {
    func naturalCompare(_ other: String, ignoreCase: Bool = true, likeFileNames: Bool = false) -> Int {
        NaturalComparator.compare(
            Array(utf16),
            Array(other.utf16),
            ignoreCase: ignoreCase,
            likeFileNames: likeFileNames
        )
    }

    func isNaturallyOrdered(before other: String) -> Bool {
        naturalCompare(other) < 0
    }
}
