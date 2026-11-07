import CoreGraphics
import Testing
@testable import Dreamder

@Suite
struct SplitLayoutMathTests {
    private static let divider: CGFloat = 7
    private static let minimum: CGFloat = 100
    private static let tolerance: CGFloat = 1e-9

    private func twoPanes(first: CGFloat = 0.5, minimum: CGFloat = SplitLayoutMathTests.minimum) -> SplitLayoutMath {
        SplitLayoutMath(panes: [
            SplitLayoutPane(weight: first, minLength: minimum),
            SplitLayoutPane(weight: 1 - first, minLength: minimum)
        ])
    }

    private func checkBounds(_ lengths: [CGFloat], total: CGFloat, minimum: CGFloat) {
        #expect(lengths.count == 2)
        #expect(lengths.allSatisfy { $0 >= 0 })
        if total <= Self.divider {
            #expect(lengths == [0, 0])
            return
        }
        #expect(abs(lengths.reduce(0, +) - (total - Self.divider)) < Self.tolerance)
        if lengths[0] == 0 || lengths[1] == 0 { return }
        let belowMinimum = lengths.map { $0 < minimum }
        #expect(belowMinimum[0] == belowMinimum[1])
    }

    @Test(arguments: [500, 300, 150, 100, 10, 8, 7, 3, 0] as [CGFloat])
    func simpleRatioHonoursMinimumsOnBothAxes(total: CGFloat) {
        let math = twoPanes()
        let lengths = math.distribute(length: total, dividerThickness: Self.divider)
        checkBounds(lengths, total: total, minimum: Self.minimum)
    }

    @Test
    func proportionSweepKeepsMinimumsAtComfortableSize() {
        let total: CGFloat = 500
        for step in 0...100 {
            let proportion = CGFloat(step) / 100
            let lengths = twoPanes(first: proportion).distribute(length: total, dividerThickness: Self.divider)
            checkBounds(lengths, total: total, minimum: Self.minimum)
            #expect(lengths.allSatisfy { $0 >= Self.minimum })
        }
    }

    @Test
    func proportionRoundTripsThroughLayout() {
        let total: CGFloat = 1007
        let available = total - Self.divider
        for step in 0...100 {
            let proportion = CGFloat(step) / 100
            let math = twoPanes(first: proportion, minimum: 0)
            let lengths = math.distribute(length: total, dividerThickness: Self.divider)
            #expect(abs(lengths.reduce(0, +) - available) < Self.tolerance)
            let recovered = math.weights(forLengths: lengths)
            #expect(abs(recovered[0] - proportion) <= 1 / available)
            #expect(abs(recovered.reduce(0, +) - 1) < Self.tolerance)
        }
    }

    @Test
    func largeProportionThenShrinkToMinimumTotal() {
        let math = twoPanes(first: 0.9)
        for total in [500, 300, 100] as [CGFloat] {
            checkBounds(math.distribute(length: total, dividerThickness: Self.divider), total: total, minimum: Self.minimum)
        }
        #expect(math.distribute(length: 500, dividerThickness: Self.divider) == [393, 100])
    }

    @Test
    func smallProportionThenGrowThroughMinimumTotal() {
        let math = twoPanes(first: 0.1)
        for total in [10, 100, 150, 500] as [CGFloat] {
            checkBounds(math.distribute(length: total, dividerThickness: Self.divider), total: total, minimum: Self.minimum)
        }
        #expect(math.distribute(length: 500, dividerThickness: Self.divider) == [100, 393])
    }

    @Test
    func totalNotLargerThanDividerCollapsesEverything() {
        let math = twoPanes()
        #expect(math.distribute(length: Self.divider, dividerThickness: Self.divider) == [0, 0])
        #expect(math.distribute(length: 3, dividerThickness: Self.divider) == [0, 0])
        #expect(math.distribute(length: 0, dividerThickness: Self.divider) == [0, 0])
        #expect(math.distribute(length: -20, dividerThickness: Self.divider) == [0, 0])
        #expect(math.distribute(length: .infinity, dividerThickness: Self.divider) == [0, 0])
    }

    @Test
    func lackOfSpaceSharesByMinimumRatio() {
        let math = SplitLayoutMath(panes: [
            SplitLayoutPane(weight: 0.9, minLength: 100),
            SplitLayoutPane(weight: 0.1, minLength: 300)
        ])
        let lengths = math.distribute(length: 207, dividerThickness: 7)
        #expect(lengths == [50, 150])
    }

    @Test
    func waterFillingPinsMaximumsAndRedistributes() {
        let math = SplitLayoutMath(panes: [
            SplitLayoutPane(weight: 1, maxLength: 50),
            SplitLayoutPane(weight: 1),
            SplitLayoutPane(weight: 1)
        ])
        #expect(math.distribute(length: 302, dividerThickness: 1) == [50, 125, 125])

        let cascading = SplitLayoutMath(panes: [
            SplitLayoutPane(weight: 1, maxLength: 50),
            SplitLayoutPane(weight: 1, maxLength: 50),
            SplitLayoutPane(weight: 1)
        ])
        #expect(cascading.distribute(length: 302, dividerThickness: 1) == [50, 50, 200])
    }

    @Test
    func waterFillingPinsMinimumsAndRedistributes() {
        let math = SplitLayoutMath(panes: [
            SplitLayoutPane(weight: 1, minLength: 150),
            SplitLayoutPane(weight: 3)
        ])
        #expect(math.distribute(length: 401, dividerThickness: 1) == [150, 250])

        let three = SplitLayoutMath(panes: [
            SplitLayoutPane(weight: 1, minLength: 120),
            SplitLayoutPane(weight: 1, minLength: 120),
            SplitLayoutPane(weight: 4)
        ])
        #expect(three.distribute(length: 602, dividerThickness: 1) == [120, 120, 360])
    }

    @Test
    func equalWeightsPutRoundingRemainderOnLastPane() {
        let math = SplitLayoutMath(panes: [SplitLayoutPane(), SplitLayoutPane(), SplitLayoutPane()])
        #expect(math.distribute(length: 100, dividerThickness: 0) == [33, 33, 34])
    }

    @Test
    func roundingRemainderAvoidsPanesPinnedAtMaximum() {
        let math = SplitLayoutMath(panes: [
            SplitLayoutPane(),
            SplitLayoutPane(),
            SplitLayoutPane(),
            SplitLayoutPane(maxLength: 10)
        ])
        let lengths = math.distribute(length: 102, dividerThickness: 0)
        #expect(lengths == [31, 31, 30, 10])
    }

    @Test
    func unusedSpaceRemainsWhenEveryPaneIsCapped() {
        let math = SplitLayoutMath(panes: [
            SplitLayoutPane(maxLength: 50),
            SplitLayoutPane(maxLength: 60)
        ])
        #expect(math.distribute(length: 301, dividerThickness: 1) == [50, 60])
    }

    @Test
    func distributionIsDeterministic() {
        let math = SplitLayoutMath(panes: [
            SplitLayoutPane(weight: 0.37, minLength: 40),
            SplitLayoutPane(weight: 0.21, maxLength: 90),
            SplitLayoutPane(weight: 0.42, minLength: 10)
        ])
        let first = math.distribute(length: 777.5, dividerThickness: 3)
        for _ in 0..<20 {
            #expect(math.distribute(length: 777.5, dividerThickness: 3) == first)
        }
        #expect(abs(first.reduce(0, +) - (777.5 - 6)) < Self.tolerance)
    }

    @Test
    func collapsedPaneGetsZeroAndItsDividerDisappears() {
        let math = SplitLayoutMath(panes: [
            SplitLayoutPane(),
            SplitLayoutPane(isCollapsed: true),
            SplitLayoutPane()
        ])
        #expect(math.visibleIndices == [0, 2])
        #expect(math.distribute(length: 201, dividerThickness: 1) == [100, 0, 100])
    }

    @Test
    func singleVisiblePaneFillsTheWholeLength() {
        let math = SplitLayoutMath(panes: [
            SplitLayoutPane(isCollapsed: true),
            SplitLayoutPane(minLength: 500, maxLength: 600),
            SplitLayoutPane(isCollapsed: true)
        ])
        #expect(math.distribute(length: 300, dividerThickness: 7) == [0, 300, 0])
    }

    @Test
    func everyPaneCollapsedYieldsZeros() {
        let math = SplitLayoutMath(panes: [SplitLayoutPane(isCollapsed: true), SplitLayoutPane(isCollapsed: true)])
        #expect(math.distribute(length: 300, dividerThickness: 7) == [0, 0])
        #expect(SplitLayoutMath(panes: []).distribute(length: 300, dividerThickness: 7).isEmpty)
    }

    @Test
    func collapsedPaneKeepsItsWeight() {
        let math = SplitLayoutMath(panes: [
            SplitLayoutPane(weight: 0.4),
            SplitLayoutPane(weight: 0.2, isCollapsed: true),
            SplitLayoutPane(weight: 0.4)
        ])
        let weights = math.drag(dividerIndex: 0, delta: 100, lengths: [200, 0, 200])
        #expect(weights.count == 3)
        #expect(abs(weights[0] - 0.6) < Self.tolerance)
        #expect(abs(weights[1] - 0.2) < Self.tolerance)
        #expect(abs(weights[2] - 0.2) < Self.tolerance)
    }

    @Test
    func dragMovesTheDividerByDelta() {
        let math = twoPanes()
        let weights = math.drag(dividerIndex: 0, delta: 50, lengths: [200, 200])
        #expect(abs(weights[0] - 0.625) < Self.tolerance)
        #expect(abs(weights[1] - 0.375) < Self.tolerance)
    }

    @Test
    func dragClampsAtBothMinimums() {
        let math = twoPanes()
        let right = math.drag(dividerIndex: 0, delta: 500, lengths: [200, 200])
        #expect(abs(right[0] - 0.75) < Self.tolerance)
        let left = math.drag(dividerIndex: 0, delta: -500, lengths: [200, 200])
        #expect(abs(left[0] - 0.25) < Self.tolerance)
    }

    @Test
    func dragClampsAtMaximums() {
        let math = SplitLayoutMath(panes: [
            SplitLayoutPane(minLength: 100, maxLength: 250),
            SplitLayoutPane(minLength: 100, maxLength: 220)
        ])
        let right = math.drag(dividerIndex: 0, delta: 500, lengths: [200, 200])
        #expect(abs(right[0] - 0.625) < Self.tolerance)
        let left = math.drag(dividerIndex: 0, delta: -500, lengths: [200, 200])
        #expect(abs(left[0] - 0.45) < Self.tolerance)
    }

    @Test
    func dragOnlyAffectsTheTwoNeighbours() {
        let math = SplitLayoutMath(panes: [SplitLayoutPane(), SplitLayoutPane(), SplitLayoutPane()])
        let weights = math.drag(dividerIndex: 1, delta: -30, lengths: [100, 100, 100])
        #expect(abs(weights[0] - 100.0 / 300) < Self.tolerance)
        #expect(abs(weights[1] - 70.0 / 300) < Self.tolerance)
        #expect(abs(weights[2] - 130.0 / 300) < Self.tolerance)
    }

    @Test
    func dragNeverShrinksAPaneBelowItsMinimum() {
        let math = twoPanes()
        let blocked = math.drag(dividerIndex: 0, delta: -40, lengths: [60, 190])
        #expect(abs(blocked[0] - 60.0 / 250) < Self.tolerance)
        let grown = math.drag(dividerIndex: 0, delta: 20, lengths: [60, 190])
        #expect(abs(grown[0] - 80.0 / 250) < Self.tolerance)
        let starved = math.drag(dividerIndex: 0, delta: 20, lengths: [60, 90])
        #expect(abs(starved[0] - 60.0 / 150) < Self.tolerance)
    }

    @Test
    func dragWithInvalidInputKeepsWeights() {
        let math = twoPanes(first: 0.25)
        #expect(math.drag(dividerIndex: 5, delta: 10, lengths: [200, 200]) == [0.25, 0.75])
        #expect(math.drag(dividerIndex: -1, delta: 10, lengths: [200, 200]) == [0.25, 0.75])
        #expect(math.drag(dividerIndex: 0, delta: 10, lengths: [200]) == [0.25, 0.75])
        #expect(math.drag(dividerIndex: 0, delta: .nan, lengths: [200, 200]) == [0.25, 0.75])
    }

    @Test
    func resizeGivesTheWholeDeltaToTheLowestHoldingPriority() {
        let math = SplitLayoutMath(panes: [
            SplitLayoutPane(holdingPriority: 1000),
            SplitLayoutPane(holdingPriority: 250)
        ])
        let grown = math.resize(lengths: [300, 300], newLength: 800, dividerThickness: 0)
        #expect(abs(grown[0] - 0.375) < Self.tolerance)
        #expect(abs(grown[1] - 0.625) < Self.tolerance)
        let shrunk = math.resize(lengths: [300, 300], newLength: 400, dividerThickness: 0)
        #expect(abs(shrunk[0] - 0.75) < Self.tolerance)
        #expect(abs(shrunk[1] - 0.25) < Self.tolerance)
    }

    @Test
    func resizeSpillsToHigherPriorityWhenTheFlexiblePaneIsExhausted() {
        let math = SplitLayoutMath(panes: [
            SplitLayoutPane(holdingPriority: 1000),
            SplitLayoutPane(minLength: 50, holdingPriority: 250)
        ])
        let weights = math.resize(lengths: [300, 300], newLength: 300, dividerThickness: 0)
        #expect(abs(weights[0] - 250.0 / 300) < Self.tolerance)
        #expect(abs(weights[1] - 50.0 / 300) < Self.tolerance)
    }

    @Test
    func resizeWithEqualPrioritiesKeepsProportions() {
        let math = SplitLayoutMath(panes: [SplitLayoutPane(), SplitLayoutPane(), SplitLayoutPane()])
        let weights = math.resize(lengths: [100, 200, 300], newLength: 1200, dividerThickness: 0)
        #expect(abs(weights[0] - 1.0 / 6) < Self.tolerance)
        #expect(abs(weights[1] - 2.0 / 6) < Self.tolerance)
        #expect(abs(weights[2] - 3.0 / 6) < Self.tolerance)
    }

    @Test
    func resizeRespectsMaximumOfTheFlexiblePane() {
        let math = SplitLayoutMath(panes: [
            SplitLayoutPane(holdingPriority: 1000),
            SplitLayoutPane(maxLength: 350, holdingPriority: 250)
        ])
        let weights = math.resize(lengths: [300, 300], newLength: 800, dividerThickness: 0)
        #expect(abs(weights[0] - 450.0 / 800) < Self.tolerance)
        #expect(abs(weights[1] - 350.0 / 800) < Self.tolerance)
    }

    @Test
    func equalizeResetsEveryWeight() {
        let math = SplitLayoutMath(panes: [
            SplitLayoutPane(weight: 0.7),
            SplitLayoutPane(weight: 0.2),
            SplitLayoutPane(weight: 0.1)
        ])
        let weights = math.equalize()
        #expect(weights.count == 3)
        #expect(weights.allSatisfy { abs($0 - 1.0 / 3) < Self.tolerance })
        #expect(SplitLayoutMath(panes: []).equalize().isEmpty)
    }

    @Test
    func mismatchedOrInvalidWeightsFallBackToEqualShares() {
        #expect(SplitLayoutMath.normalizedWeights([0.5], count: 2) == [0.5, 0.5])
        #expect(SplitLayoutMath.normalizedWeights([0.2, 0.3, 0.5], count: 2) == [0.5, 0.5])
        #expect(SplitLayoutMath.normalizedWeights([-1, 2], count: 2) == [0.5, 0.5])
        #expect(SplitLayoutMath.normalizedWeights([.nan, 1], count: 2) == [0.5, 0.5])
        #expect(SplitLayoutMath.normalizedWeights([0, 0], count: 2) == [0.5, 0.5])
        #expect(SplitLayoutMath.normalizedWeights([], count: 0).isEmpty)
        #expect(SplitLayoutMath.normalizedWeights([2, 6], count: 2) == [0.25, 0.75])
    }

    @Test
    func validityRequiresMatchingCountAndNonNegativeFiniteWeights() {
        #expect(SplitLayoutMath.isValid(weights: [0.5, 0.5], count: 2))
        #expect(SplitLayoutMath.isValid(weights: [0, 1], count: 2))
        #expect(!SplitLayoutMath.isValid(weights: [0.5, 0.5], count: 3))
        #expect(!SplitLayoutMath.isValid(weights: [0, 0], count: 2))
        #expect(!SplitLayoutMath.isValid(weights: [-0.1, 1.1], count: 2))
        #expect(!SplitLayoutMath.isValid(weights: [.infinity, 1], count: 2))
        #expect(SplitLayoutMath.isValid(weights: [], count: 0))
    }

    @Test
    func distributionWithInvalidPaneWeightsSplitsEqually() {
        let math = SplitLayoutMath(panes: [SplitLayoutPane(weight: -1), SplitLayoutPane(weight: 1)])
        #expect(math.distribute(length: 201, dividerThickness: 1) == [100, 100])
    }

    @Test
    func weightsForLengthsKeepCollapsedWeights() {
        let math = SplitLayoutMath(panes: [
            SplitLayoutPane(weight: 0.25),
            SplitLayoutPane(weight: 0.25, isCollapsed: true),
            SplitLayoutPane(weight: 0.5)
        ])
        let weights = math.weights(forLengths: [100, 0, 300])
        #expect(abs(weights[0] - 0.1875) < Self.tolerance)
        #expect(abs(weights[1] - 0.25) < Self.tolerance)
        #expect(abs(weights[2] - 0.5625) < Self.tolerance)
    }
}
