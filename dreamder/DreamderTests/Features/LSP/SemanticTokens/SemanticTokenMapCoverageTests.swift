import CodeEditSourceEditor
import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct SemanticTokenMapCoverageTests {
    struct LineZeroOnlyRangeProvider: SemanticTokenMapRangeProvider {
        func nsRangeFrom(line: UInt32, char: UInt32, length: UInt32) -> NSRange? {
            guard line == 0 else { return nil }
            return NSRange(location: Int(char), length: Int(length))
        }
    }

    private let legend = SemanticTokensLegend(
        tokenTypes: ["keyword"],
        tokenModifiers: ["declaration", "notACaptureModifier"]
    )

    @Test
    func tokensWhoseRangeCannotBeResolvedAreSkipped() {
        let map = SemanticTokenMap(semanticCapability: .optionA(SemanticTokensOptions(legend: legend)))
        let tokens = [
            SemanticToken(line: 0, char: 1, length: 4, type: 0, modifiers: 0),
            SemanticToken(line: 7, char: 0, length: 3, type: 0, modifiers: 0),
            SemanticToken(line: 0, char: 9, length: 2, type: 0, modifiers: 0)
        ]

        let decoded = map.decode(tokens: tokens, using: LineZeroOnlyRangeProvider())

        #expect(decoded.map(\.range) == [NSRange(location: 1, length: 4), NSRange(location: 9, length: 2)])
    }

    @Test
    func unknownAndOutOfLegendModifierBitsAreIgnored() {
        let map = SemanticTokenMap(semanticCapability: .optionA(SemanticTokensOptions(legend: legend)))

        #expect(map.decodeModifier(0b10) == [])
        #expect(map.decodeModifier(1 << 20) == [])
        #expect(map.decodeModifier(0b1 | 0b10 | (1 << 20)) == [.declaration])
    }
}
