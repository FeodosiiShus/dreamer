import CoreGraphics
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct IslandsLayoutMetricsTests {
    private static let area = CGSize(width: 1000, height: 700)

    private static let all = IslandsLayoutMetrics.Input(
        hasLeft: true,
        leftWidth: 280,
        hasBottom: true,
        bottomHeight: 300,
        bottomMaximized: false
    )

    private static let densities = [IslandsLayoutMetrics.compact, IslandsLayoutMetrics.regular]

    private func inner(_ metrics: IslandsLayoutMetrics, in area: CGSize = IslandsLayoutMetricsTests.area) -> CGRect {
        CGRect(origin: CGPoint(x: metrics.gap, y: metrics.gap), size: metrics.innerSize(of: area))
    }

    @Test
    func densitiesUseTheIntelliJIslandArcAndBorderWidth() {
        #expect(IslandsLayoutMetrics.compact.gap == 4)
        #expect(IslandsLayoutMetrics.compact.radius == 8)
        #expect(IslandsLayoutMetrics.regular.gap == 6)
        #expect(IslandsLayoutMetrics.regular.radius == 10)
        #expect(IslandsLayoutMetrics.make(isCompact: true) == .compact)
        #expect(IslandsLayoutMetrics.make(isCompact: false) == .regular)
    }

    @Test
    func theInnerAreaLosesOneGapOnEverySide() {
        for metrics in Self.densities {
            let size = metrics.innerSize(of: Self.area)

            #expect(size.width == Self.area.width - 2 * metrics.gap)
            #expect(size.height == Self.area.height - 2 * metrics.gap)
        }
        #expect(IslandsLayoutMetrics.regular.innerSize(of: CGSize(width: 5, height: 3)) == .zero)
    }

    @Test
    func everyIslandIsInsetByTheGapFromEveryWindowEdge() {
        for metrics in Self.densities {
            let frames = metrics.frames(in: Self.area, input: Self.all)

            #expect(frames.islands.count == 3)
            for island in frames.islands {
                #expect(island.minX >= metrics.gap)
                #expect(island.minY >= metrics.gap)
                #expect(island.maxX <= Self.area.width - metrics.gap)
                #expect(island.maxY <= Self.area.height - metrics.gap)
            }
        }
    }

    @Test
    func islandsNeverOverlapAndDividersFillExactlyOneGapBetweenNeighbours() {
        for metrics in Self.densities {
            let frames = metrics.frames(in: Self.area, input: Self.all)

            #expect(frames.left.maxX + metrics.gap == frames.editor.minX)
            #expect(frames.leftDivider.minX == frames.left.maxX)
            #expect(frames.leftDivider.width == metrics.gap)
            #expect(frames.leftDivider.maxX == frames.editor.minX)
            #expect(frames.leftDivider.height == frames.left.height)
            #expect(frames.editor.maxY + metrics.gap == frames.bottom.minY)
            #expect(frames.bottomDivider.minY == frames.editor.maxY)
            #expect(frames.bottomDivider.height == metrics.gap)
            #expect(frames.bottomDivider.maxY == frames.bottom.minY)
            #expect(frames.bottomDivider.width == frames.bottom.width)
            #expect(frames.left.minX == metrics.gap)
            #expect(frames.left.minY == frames.editor.minY)
            #expect(frames.editor.maxX == Self.area.width - metrics.gap)
            #expect(frames.bottom.maxY == Self.area.height - metrics.gap)
            #expect(frames.bottom.minX == metrics.gap)
            #expect(frames.bottom.maxX == Self.area.width - metrics.gap)
            #expect(!frames.left.intersects(frames.editor))
            #expect(!frames.editor.intersects(frames.bottom))
            #expect(!frames.left.intersects(frames.bottom))
            #expect(frames.dividers == [frames.leftDivider, frames.bottomDivider])
        }
    }

    @Test
    func sizesFollowTheStoredLengthsWithinTheClampLimits() {
        let metrics = IslandsLayoutMetrics.compact
        let frames = metrics.frames(in: Self.area, input: Self.all)
        let limit = inner(metrics)

        #expect(frames.left.width == 280)
        #expect(frames.bottom.height == 300)

        var tooSmall = Self.all
        tooSmall.leftWidth = 10
        tooSmall.bottomHeight = 10
        let minimal = metrics.frames(in: Self.area, input: tooSmall)
        #expect(minimal.left.width == ToolWindowLayout.minLeftWidth)
        #expect(minimal.bottom.height == ToolWindowLayout.minBottomHeight)

        var tooLarge = Self.all
        tooLarge.leftWidth = 5000
        tooLarge.bottomHeight = 5000
        let maximal = metrics.frames(in: Self.area, input: tooLarge)
        #expect(maximal.left.width == ToolWindowLayout.clampLeftWidth(5000, availableWidth: limit.width))
        #expect(maximal.bottom.height == ToolWindowLayout.clampBottomHeight(5000, availableHeight: limit.height))
        #expect(maximal.editor.width >= ToolWindowLayout.minEditorWidth - metrics.gap)
        #expect(maximal.editor.height >= ToolWindowLayout.minEditorHeight - metrics.gap)
    }

    @Test
    func theEditorAloneFillsTheInnerAreaAndKeepsTheGapAtEveryEdge() {
        for metrics in Self.densities {
            let input = IslandsLayoutMetrics.Input(
                hasLeft: false,
                leftWidth: 280,
                hasBottom: false,
                bottomHeight: 300,
                bottomMaximized: false
            )
            let frames = metrics.frames(in: Self.area, input: input)

            #expect(frames.editor == inner(metrics))
            #expect(frames.left == .zero)
            #expect(frames.bottom == .zero)
            #expect(frames.dividers.isEmpty)
            #expect(frames.islands == [frames.editor])
        }
    }

    @Test
    func aMissingLeftOrBottomWindowGivesItsSpaceToTheEditor() {
        let metrics = IslandsLayoutMetrics.regular
        var leftOnly = Self.all
        leftOnly.hasBottom = false
        var bottomOnly = Self.all
        bottomOnly.hasLeft = false

        let withLeft = metrics.frames(in: Self.area, input: leftOnly)
        let withBottom = metrics.frames(in: Self.area, input: bottomOnly)

        #expect(withLeft.editor.maxY == Self.area.height - metrics.gap)
        #expect(withLeft.bottom == .zero)
        #expect(withLeft.bottomDivider == .zero)
        #expect(withLeft.dividers == [withLeft.leftDivider])
        #expect(withBottom.editor.minX == metrics.gap)
        #expect(withBottom.left == .zero)
        #expect(withBottom.leftDivider == .zero)
        #expect(withBottom.dividers == [withBottom.bottomDivider])
    }

    @Test
    func aMaximizedBottomWindowTakesTheWholeInnerAreaWhenOneExists() {
        for metrics in Self.densities {
            var maximized = Self.all
            maximized.bottomMaximized = true
            let frames = metrics.frames(in: Self.area, input: maximized)

            #expect(frames.bottom == inner(metrics))
            #expect(frames.editor == .zero)
            #expect(frames.left == .zero)
            #expect(frames.islands == [frames.bottom])

            maximized.hasBottom = false
            let withoutBottom = metrics.frames(in: Self.area, input: maximized)
            #expect(withoutBottom.bottom == .zero)
            #expect(withoutBottom.editor.minX > metrics.gap)
        }
    }

    @Test
    func framesAreLookedUpBySlot() {
        let frames = IslandsLayoutMetrics.regular.frames(in: Self.area, input: Self.all)

        #expect(frames.frame(for: .left) == frames.left)
        #expect(frames.frame(for: .leftDivider) == frames.leftDivider)
        #expect(frames.frame(for: .editor) == frames.editor)
        #expect(frames.frame(for: .bottomDivider) == frames.bottomDivider)
        #expect(frames.frame(for: .bottom) == frames.bottom)
    }

    @Test
    func aTinyAreaNeverProducesNegativeSizes() {
        let frames = IslandsLayoutMetrics.regular.frames(in: CGSize(width: 20, height: 20), input: Self.all)

        for frame in [frames.left, frames.editor, frames.bottom, frames.leftDivider, frames.bottomDivider] {
            #expect(frame.width >= 0)
            #expect(frame.height >= 0)
        }
    }
}
