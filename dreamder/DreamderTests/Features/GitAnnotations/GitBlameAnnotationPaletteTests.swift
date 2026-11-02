import AppKit
import Testing
@testable import Dreamder

@Suite
struct GitBlameAnnotationPaletteTests {
    private func components(_ color: NSColor) -> [Int] {
        guard let srgb = color.usingColorSpace(.sRGB) else { return [] }
        return [
            Int((srgb.redComponent * 255).rounded()),
            Int((srgb.greenComponent * 255).rounded()),
            Int((srgb.blueComponent * 255).rounded())
        ]
    }

    @Test
    func newestCommitUsesTheRecentShade() {
        let tint = GitBlameAnnotationPalette.tint(ageFraction: 0, alternate: false)
        #expect(components(tint) == [0x2F, 0x51, 0x94])
    }

    @Test
    func oldestCommitUsesTheDimmestShade() {
        let tint = GitBlameAnnotationPalette.tint(ageFraction: 1, alternate: false)
        #expect(components(tint) == [0x22, 0x25, 0x2E])
    }

    @Test
    func ageFractionIsClamped() {
        let before = GitBlameAnnotationPalette.tint(ageFraction: -3, alternate: false)
        let after = GitBlameAnnotationPalette.tint(ageFraction: 4, alternate: false)
        #expect(components(before) == [0x2F, 0x51, 0x94])
        #expect(components(after) == [0x22, 0x25, 0x2E])
    }

    @Test
    func alternatingCommitsUseDifferentShades() {
        let even = GitBlameAnnotationPalette.tint(ageFraction: 0.5, alternate: false)
        let odd = GitBlameAnnotationPalette.tint(ageFraction: 0.5, alternate: true)
        #expect(components(even) != components(odd))
        #expect(components(odd)[0] > components(even)[0])
    }
}
