import Foundation
import Testing
@testable import Dreamder

@Suite
struct MarkdownPreviewStylesCoverageTests {
    private static let huesBySector: [MarkdownPreviewColor] = [
        MarkdownPreviewColor(red: 200, green: 100, blue: 50),
        MarkdownPreviewColor(red: 100, green: 200, blue: 50),
        MarkdownPreviewColor(red: 50, green: 200, blue: 100),
        MarkdownPreviewColor(red: 50, green: 100, blue: 200),
        MarkdownPreviewColor(red: 100, green: 50, blue: 200),
        MarkdownPreviewColor(red: 200, green: 50, blue: 100)
    ]

    @Test
    func brightnessTuningRoundTripsEveryHueSector() {
        for color in Self.huesBySector {
            let same = color.brighter(tones: 0)
            #expect(abs(same.red - color.red) <= 1, "\(color)")
            #expect(abs(same.green - color.green) <= 1, "\(color)")
            #expect(abs(same.blue - color.blue) <= 1, "\(color)")
        }
    }

    @Test
    func brighterAndDarkerMoveLuminanceInEveryHueSector() {
        for color in Self.huesBySector {
            #expect(color.brighter(tones: 2).luminance > color.luminance, "\(color)")
            #expect(color.darker(tones: 2).luminance < color.luminance, "\(color)")
        }
    }

    @Test
    func ensuringContrastStopsWhenTheColorCannotMoveFurther() {
        let white = MarkdownPreviewColor(red: 255, green: 255, blue: 255)
        #expect(white.ensuringContrast(against: white, atLeast: 25) == white)
    }

    @Test
    func ensuringContrastShiftsTowardsTheRequiredRatio() {
        let background = MarkdownPreviewColor(red: 25, green: 26, blue: 28)
        let dim = MarkdownPreviewColor(red: 60, green: 62, blue: 66)
        let shifted = dim.ensuringContrast(against: background, atLeast: 3)
        #expect(shifted.contrast(with: background) >= 3)
        #expect(shifted.luminance > dim.luminance)
    }
}
