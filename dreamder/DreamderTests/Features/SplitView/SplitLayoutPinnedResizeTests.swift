import CoreGraphics
import Testing
@testable import Dreamder

@Suite
struct SplitLayoutPinnedResizeTests {
    private static let tolerance: CGFloat = 1e-9

    @Test
    func resizeBeyondEveryMaximumPinsEveryPaneAtItsMaximum() throws {
        let math = SplitLayoutMath(panes: [
            SplitLayoutPane(maxLength: 150),
            SplitLayoutPane(maxLength: 250)
        ])

        let weights = math.resize(lengths: [100, 200], newLength: 1000, dividerThickness: 0)

        let first = try #require(weights.first)
        let last = try #require(weights.last)
        #expect(weights.count == 2)
        #expect(abs(first - 150.0 / 400) < Self.tolerance)
        #expect(abs(last - 250.0 / 400) < Self.tolerance)
    }

    @Test
    func resizeBelowEveryMinimumPinsEveryPaneAtItsMinimum() throws {
        let math = SplitLayoutMath(panes: [
            SplitLayoutPane(minLength: 40),
            SplitLayoutPane(minLength: 60)
        ])

        let weights = math.resize(lengths: [100, 200], newLength: 10, dividerThickness: 0)

        let first = try #require(weights.first)
        let last = try #require(weights.last)
        #expect(weights.count == 2)
        #expect(abs(first - 0.4) < Self.tolerance)
        #expect(abs(last - 0.6) < Self.tolerance)
    }
}
