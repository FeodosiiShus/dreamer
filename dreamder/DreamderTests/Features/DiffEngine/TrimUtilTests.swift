import Testing
import Foundation
@testable import Dreamder

private let chSmile = "\u{1F602}"
private let chMan = "\u{1F9D2}"

private let punctuationCharacters: Set<Int> = Set("(){}[],./?`~!@#$%^&*-=+|\\;:'\"<>".unicodeScalars.map { Int($0.value) })

private func assertIsAlpha(_ text: String, _ expected: Bool) {
    for scalar in text.unicodeScalars {
        #expect(TrimUtil.isAlpha(Int(scalar.value)) == expected, "\(scalar) - \(scalar.value)")
    }
}

private func assertIsContinuous(_ text: String, _ expected: Bool) {
    for scalar in text.unicodeScalars {
        #expect(TrimUtil.isContinuousScript(Int(scalar.value)) == expected, "\(scalar) - \(scalar.value)")
    }
}

@Suite struct TrimUtilTests {
    @Test func testPunctuation() {
        let mismatches = (0...Int(UInt16.max)).filter { code in
            TrimUtil.isPunctuation(code) != punctuationCharacters.contains(code)
        }
        #expect(mismatches.isEmpty, "mismatched code units: \(mismatches)")
    }

    @Test func testContinuousScript() {
        assertIsAlpha("!? \t\n+~", false)

        assertIsAlpha("AB12", true)
        assertIsAlpha("АБВ汉语日ひรไ", true)
        assertIsAlpha("óèäñĀ", true)
        assertIsAlpha("\r_\u{0001}", true)
        assertIsAlpha("\(chSmile)\(chMan)", true)

        assertIsContinuous("12_ABZ", false)
        assertIsContinuous("АБВ", false)
        assertIsContinuous("ʁit", false)
        assertIsContinuous("음훈", false)
        assertIsContinuous("óèäñĀ", false)
        assertIsContinuous("\r_\u{0001}", false)

        assertIsContinuous("象形文字", true)
        assertIsContinuous("อักษรไ", true)
        assertIsContinuous("ひらがなカタカナ日本語", true)
        assertIsContinuous("汉语漢語", true)
        assertIsContinuous("☺♥", true)
        assertIsContinuous("\(chSmile)\(chMan)", true)
        assertIsContinuous("\u{200e}\u{200f}\u{061c}", true)
    }
}
